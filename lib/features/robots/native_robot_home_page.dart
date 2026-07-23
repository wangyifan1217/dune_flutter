import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'robot_models.dart';
import 'robot_widgets.dart';

/// 机器人主页：工作流场景 / 角色库（静态预览，对齐参考风格）。
class NativeRobotHomePage extends StatefulWidget {
  const NativeRobotHomePage({
    super.key,
    required this.onBack,
    required this.onRunScenario,
    this.initialTab = 0,
  });

  final VoidCallback onBack;
  final ValueChanged<String> onRunScenario;
  final int initialTab;

  @override
  State<NativeRobotHomePage> createState() => _NativeRobotHomePageState();
}

class _NativeRobotHomePageState extends State<NativeRobotHomePage> {
  late int _tab;
  String _query = '';
  String _category = '全部';
  String? _selectedRoleId;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 1);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: RobotTheme.pageBg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: RobotSearchField(
                hint: _tab == 0 ? '搜索工作流场景' : '搜索数字员工',
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            Expanded(
              child: _tab == 0 ? _buildScenarios() : _buildRoles(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tab == 0 ? '工作流场景' : '角色库',
                  style: DunesTypography.sans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: RobotTheme.text,
                  ),
                ),
                Text(
                  _tab == 0
                      ? '对接 N8N · 静态预览'
                      : '${RobotCatalog.roles.length} 位数字员工',
                  style: DunesTypography.sans(
                    fontSize: 12,
                    color: RobotTheme.text3,
                  ),
                ),
              ],
            ),
          ),
          _Segment(
            tab: _tab,
            onChanged: (v) => setState(() => _tab = v),
          ),
        ],
      ),
    );
  }

  Widget _buildScenarios() {
    final q = _query.toLowerCase();
    final list = RobotCatalog.scenarios.where((s) {
      if (q.isEmpty) return true;
      return s.title.toLowerCase().contains(q) ||
          s.desc.toLowerCase().contains(q);
    }).toList();

    if (list.isEmpty) {
      return const Center(child: Text('没有匹配的场景', style: TextStyle(color: RobotTheme.text3)));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final s = list[i];
        return RobotScenarioCard(
          scenario: s,
          onRun: () => widget.onRunScenario(s.id),
        );
      },
    );
  }

  Widget _buildRoles() {
    final q = _query.toLowerCase();
    final list = RobotCatalog.roles.where((r) {
      if (_category != '全部' && r.category != _category) return false;
      if (q.isEmpty) return true;
      return r.name.toLowerCase().contains(q) ||
          r.desc.toLowerCase().contains(q) ||
          r.category.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: RobotCatalog.categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = RobotCatalog.categories[i];
              final active = c == _category;
              return ChoiceChip(
                label: Text(c),
                selected: active,
                onSelected: (_) => setState(() => _category = c),
                selectedColor: RobotTheme.purple,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : RobotTheme.text2,
                ),
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: active ? RobotTheme.purple : RobotTheme.cardBorder,
                ),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: list.isEmpty
              ? const Center(
                  child: Text('没有匹配的角色', style: TextStyle(color: RobotTheme.text3)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final r = list[i];
                    return RobotRoleCard(
                      role: r,
                      selected: _selectedRoleId == r.id,
                      onTap: () => setState(() => _selectedRoleId = r.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.tab, required this.onChanged});

  final int tab;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFECEDEF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segBtn('场景', 0),
          _segBtn('角色', 1),
        ],
      ),
    );
  }

  Widget _segBtn(String label, int index) {
    final active = tab == index;
    return GestureDetector(
      onTap: () => onChanged(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? RobotTheme.purple : RobotTheme.text3,
          ),
        ),
      ),
    );
  }
}
