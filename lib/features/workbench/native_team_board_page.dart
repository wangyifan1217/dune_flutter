// native_team_board_page.dart
//
// 团队工作台 · TEAM BOARD
// 三成员协作看板：录入、勾选、删除、进度统计
// 本地持久化：SharedPreferences（如需团队同步，替换 _persist / _load 为后端接口）
//
// pubspec.yaml 依赖：
//   shared_preferences: ^2.2.0

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lighthouse/lighthouse_theme.dart';

// ═══════════════════════════════════════════════════
// 设计令牌 · 灯塔编辑风格（如接入 LhColors / LhTypography 请替换）
// ═══════════════════════════════════════════════════
class _Tokens {
  static const copper = Color(0xFFB77433);
  static const paper = Color(0xFFF6F1E8);
  static const paperDeep = Color(0xFFEEE7D8);
  static const ink = Color(0xFF1E1B18);
  static const inkSoft = Color(0xFF5A544D);
  static const mute = Color(0xFF9A9289);
  static const hairline = Color(0xFFE5DDCE);

  static const fontSans = 'PingFang SC';
  static const fontMono = 'SFMono-Regular';
  static const fontNumber = 'Inter';
}

// ═══════════════════════════════════════════════════
// 数据模型
// ═══════════════════════════════════════════════════
class _Task {
  final String id;
  String content;
  bool done;
  final DateTime createdAt;

  _Task({
    required this.id,
    required this.content,
    this.done = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'done': done,
        'createdAt': createdAt.toIso8601String(),
      };

  factory _Task.fromJson(Map<String, dynamic> j) => _Task(
        id: j['id'] as String,
        content: j['content'] as String,
        done: j['done'] as bool? ?? false,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

class _Member {
  final String key;
  final String name;
  final String pinyin;
  const _Member({required this.key, required this.name, required this.pinyin});
}

const _members = <_Member>[
  _Member(key: 'zhai', name: '翟仕琦', pinyin: 'ZHAI SHIQI'),
  _Member(key: 'wang', name: '王奕凡', pinyin: 'WANG YIFAN'),
  _Member(key: 'zhu', name: '朱子姝', pinyin: 'ZHU ZISHU'),
];

const _seedTasks = <String, List<String>>{
  'zhai': [
    '合同 PDF 解析',
    '会议纪要模版修改：上线并提供接口',
    '保险知识库：搭建完成，向保险分发平台提供对接接口',
  ],
  'wang': [
    '聊天系统优化：新增表情包、聊天记录转发',
    '审批流配置后台',
    'OA 新增合同用印申请流程',
  ],
  'zhu': [
    '汇集行政合同用印 OA 流程需求',
    '汇集人事标签四需求',
    '灯塔细节修复与优化',
    '提案导入',
  ],
};

// ═══════════════════════════════════════════════════
// 主页面
// ═══════════════════════════════════════════════════
class NativeTeamBoardPage extends StatefulWidget {
  const NativeTeamBoardPage({super.key});

  @override
  State<NativeTeamBoardPage> createState() => _NativeTeamBoardPageState();
}

class _NativeTeamBoardPageState extends State<NativeTeamBoardPage> {
  final Map<String, List<_Task>> _tasks = {
    for (final m in _members) m.key: <_Task>[],
  };
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    bool anyExisting = false;
    for (final m in _members) {
      final raw = sp.getString('team_board_${m.key}');
      if (raw != null) {
        anyExisting = true;
        _tasks[m.key] = (json.decode(raw) as List)
            .map((e) => _Task.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    // 首次进入 → 灌入种子
    if (!anyExisting) {
      for (final entry in _seedTasks.entries) {
        _tasks[entry.key] = [
          for (int i = 0; i < entry.value.length; i++)
            _Task(id: '${entry.key}_seed_$i', content: entry.value[i]),
        ];
      }
      for (final m in _members) {
        await _persist(m.key);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _persist(String key) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      'team_board_$key',
      json.encode(_tasks[key]!.map((t) => t.toJson()).toList()),
    );
  }

  void _toggle(String key, String id) {
    setState(() {
      final t = _tasks[key]!.firstWhere((e) => e.id == id);
      t.done = !t.done;
    });
    _persist(key);
  }

  void _add(String key, String content) {
    final text = content.trim();
    if (text.isEmpty) return;
    setState(() {
      _tasks[key]!.add(_Task(
        id: '${key}_${DateTime.now().millisecondsSinceEpoch}',
        content: text,
      ));
    });
    _persist(key);
  }

  void _delete(String key, String id) {
    setState(() {
      _tasks[key]!.removeWhere((e) => e.id == id);
    });
    _persist(key);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _Tokens.paper,
        body: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation(_Tokens.copper),
            ),
          ),
        ),
      );
    }

    final total = _tasks.values.fold<int>(0, (s, l) => s + l.length);
    final done = _tasks.values
        .fold<int>(0, (s, l) => s + l.where((t) => t.done).length);

    return Scaffold(
      backgroundColor: _Tokens.paper,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, cons) {
            final wide = cons.maxWidth >= 960;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 48 : 24,
                vertical: 40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHero(total, done),
                  const SizedBox(height: 40),
                  if (wide)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (int i = 0; i < _members.length; i++) ...[
                            Expanded(child: _buildColumn(_members[i])),
                            if (i != _members.length - 1)
                              Container(
                                width: 1,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                color: _Tokens.hairline,
                              ),
                          ],
                        ],
                      ),
                    )
                  else
                    Column(
                      children: [
                        for (int i = 0; i < _members.length; i++) ...[
                          _buildColumn(_members[i]),
                          if (i != _members.length - 1)
                            Container(
                              height: 1,
                              margin: const EdgeInsets.symmetric(vertical: 32),
                              color: _Tokens.hairline,
                            ),
                        ],
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHero(int total, int done) {
    final pct = total == 0 ? 0.0 : done / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '团队工作台',
          style: TextStyle(
            fontFamily: _Tokens.fontSans,
            fontSize: 32,
            fontWeight: FontWeight.w500,
            color: _Tokens.ink,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'TEAM · BOARD',
          style: TextStyle(
            fontFamily: _Tokens.fontMono,
            fontSize: 11,
            letterSpacing: 3,
            color: _Tokens.mute,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$done',
              style: const TextStyle(
                fontFamily: _Tokens.fontNumber,
                fontSize: 42,
                fontWeight: FontWeight.w300,
                color: _Tokens.copper,
                height: 1,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4),
              child: Text(
                '/ $total',
                style: const TextStyle(
                  fontFamily: _Tokens.fontNumber,
                  fontSize: 16,
                  color: _Tokens.mute,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '本周任务完成度 ${(pct * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontFamily: _Tokens.fontSans,
                  fontSize: 12,
                  color: _Tokens.inkSoft,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // 进度条
        Container(
          height: 2,
          color: _Tokens.paperDeep,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: pct,
            child: Container(color: _Tokens.copper),
          ),
        ),
      ],
    );
  }

  Widget _buildColumn(_Member m) {
    final tasks = _tasks[m.key]!;
    final done = tasks.where((t) => t.done).length;
    return _MemberColumn(
      member: m,
      tasks: tasks,
      doneCount: done,
      onToggle: (id) => _toggle(m.key, id),
      onAdd: (text) => _add(m.key, text),
      onDelete: (id) => _delete(m.key, id),
    );
  }
}

// ═══════════════════════════════════════════════════
// 成员列
// ═══════════════════════════════════════════════════
class _MemberColumn extends StatefulWidget {
  final _Member member;
  final List<_Task> tasks;
  final int doneCount;
  final void Function(String) onToggle;
  final void Function(String) onAdd;
  final void Function(String) onDelete;

  const _MemberColumn({
    required this.member,
    required this.tasks,
    required this.doneCount,
    required this.onToggle,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  State<_MemberColumn> createState() => _MemberColumnState();
}

class _MemberColumnState extends State<_MemberColumn> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim().isEmpty) return;
    widget.onAdd(_controller.text);
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 段头
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              widget.member.name,
              style: const TextStyle(
                fontFamily: _Tokens.fontSans,
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: _Tokens.ink,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                widget.member.pinyin,
                style: const TextStyle(
                  fontFamily: _Tokens.fontMono,
                  fontSize: 10,
                  letterSpacing: 2.5,
                  color: _Tokens.mute,
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '${widget.doneCount} / ${widget.tasks.length}',
                style: const TextStyle(
                  fontFamily: _Tokens.fontNumber,
                  fontSize: 12,
                  color: _Tokens.inkSoft,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(height: 1, color: _Tokens.hairline),
        // 任务
        if (widget.tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20, horizontal: 4),
            child: Text(
              '暂无任务',
              style: TextStyle(
                fontFamily: _Tokens.fontSans,
                fontSize: 12,
                color: _Tokens.mute,
              ),
            ),
          )
        else
          for (final t in widget.tasks)
            _TaskRow(
              task: t,
              onToggle: () => widget.onToggle(t.id),
              onDelete: () => widget.onDelete(t.id),
            ),
        // 输入
        const SizedBox(height: 8),
        _InputRow(
          controller: _controller,
          focus: _focus,
          onSubmit: _submit,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════
// 任务行
// ═══════════════════════════════════════════════════
class _TaskRow extends StatefulWidget {
  final _Task task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _TaskRow({
    required this.task,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final done = widget.task.done;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _Tokens.hairline)),
        ),
        child: InkWell(
          onTap: widget.onToggle,
          hoverColor: _Tokens.paperDeep.withOpacity(0.5),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _Checkbox(checked: done),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.task.content,
                    style: TextStyle(
                      fontFamily: _Tokens.fontSans,
                      fontSize: 14,
                      height: 1.5,
                      color: done ? _Tokens.mute : _Tokens.ink,
                      decoration:
                          done ? TextDecoration.lineThrough : null,
                      decorationColor: _Tokens.mute,
                      decorationThickness: 1,
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: IconButton(
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.close,
                        size: 14, color: _Tokens.mute),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 24, minHeight: 24),
                    splashRadius: 16,
                    tooltip: '删除',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 勾选框
// ═══════════════════════════════════════════════════
class _Checkbox extends StatelessWidget {
  final bool checked;
  const _Checkbox({required this.checked});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: checked ? _Tokens.copper : Colors.transparent,
        border: Border.all(
          color: checked ? _Tokens.copper : _Tokens.mute,
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: checked
          ? const Icon(Icons.check, size: 12, color: _Tokens.paper)
          : null,
    );
  }
}

// ═══════════════════════════════════════════════════
// 输入行
// ═══════════════════════════════════════════════════
class _InputRow extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onSubmit;

  const _InputRow({
    required this.controller,
    required this.focus,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _Tokens.hairline)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          const Icon(Icons.add, size: 16, color: _Tokens.mute),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSubmit(),
              style: const TextStyle(
                fontFamily: _Tokens.fontSans,
                fontSize: 14,
                color: _Tokens.ink,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '添加任务，回车提交',
                hintStyle: TextStyle(
                  fontFamily: _Tokens.fontSans,
                  fontSize: 14,
                  color: _Tokens.mute,
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          InkWell(
            onTap: onSubmit,
            borderRadius: BorderRadius.circular(2),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                '添加',
                style: TextStyle(
                  fontFamily: _Tokens.fontMono,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  color: _Tokens.copper,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 「我的」tab 入口卡片
// ═══════════════════════════════════════════════════

class TeamBoardEntryCard extends StatelessWidget {
  const TeamBoardEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NativeTeamBoardPage()),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFFFFFC),
                  Color(0xFFFAF8F0),
                  Color(0xFFF2EFDF),
                ],
                stops: [0.0, 0.6, 1.0],
              ),
              border: Border.all(color: const Color(0xFFDDD5C0)),
              borderRadius: BorderRadius.circular(7),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0C0A0A0F),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: LhColors.copper.withAlpha(18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.dashboard_customize_outlined,
                    size: 18,
                    color: LhColors.copper,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '团队工作台',
                        style: LhTypography.sans(
                          size: 13,
                          color: LhColors.ink,
                          weight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '三成员协作看板 · 录入勾选 · 本地持久化',
                        style: LhTypography.sans(
                          size: 9.5,
                          color: LhColors.mute,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 16, color: LhColors.mute2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
