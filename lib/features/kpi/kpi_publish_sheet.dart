import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../profile/work_profile_kpi.dart';

const _accent = DunesColors.brandPurple;
const _line = Color(0xFFECE7F3);
const _tabular = <FontFeature>[FontFeature.tabularFigures()];

Future<List<int>?> showKpiPublishSheet({
  required BuildContext context,
  required List<WorkProfileKpiPerson> people,
  required String sector,
}) {
  return showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _KpiPublishSheet(
      people: people,
      initialSector: kpiDefaultPublishSector(people, sector),
    ),
  );
}

class _KpiPublishSheet extends StatefulWidget {
  const _KpiPublishSheet({required this.people, required this.initialSector});

  final List<WorkProfileKpiPerson> people;
  final String initialSector;

  @override
  State<_KpiPublishSheet> createState() => _KpiPublishSheetState();
}

class _KpiPublishSheetState extends State<_KpiPublishSheet> {
  late String _sector;
  final Set<String> _selected = {};

  static const _sectors = [
    MapEntry('telecom', '运营商'),
    MapEntry('energy', '能源'),
    MapEntry('rd', '研发'),
    MapEntry('office', '职能'),
  ];

  List<KpiPublishGroup> get _groups =>
      kpiPublishGroupsForSector(widget.people, sector: _sector);

  @override
  void initState() {
    super.initState();
    _sector = widget.initialSector;
  }

  void _setSector(String sector) {
    if (_sector == sector) return;
    setState(() {
      _sector = sector;
      _selected.clear();
    });
  }

  void _toggle(String name) {
    setState(() {
      if (_selected.contains(name)) {
        _selected.remove(name);
      } else {
        _selected.add(name);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selected
        ..clear()
        ..addAll([for (final group in _groups) group.name]);
    });
  }

  void _confirm() {
    final ids = <int>[];
    final seen = <int>{};
    for (final group in _groups) {
      if (!_selected.contains(group.name)) continue;
      for (final person in group.scored) {
        if (person.userId > 0 && seen.add(person.userId)) {
          ids.add(person.userId);
        }
      }
    }
    Navigator.pop(context, ids);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    final picked = [
      for (final group in groups)
        if (_selected.contains(group.name)) group,
    ];
    final scored = [for (final group in picked) ...group.scored];
    final pending = [for (final group in picked) ...group.pending];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '按项目组发布',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: DunesColors.text,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '先选板块，再选组。只发已评完的人；未评完的组会提示，但不卡住别的组。',
              style: TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final option in _sectors)
                  _chip(
                    key: Key('kpi-publish-sector-${option.key}'),
                    label: option.value,
                    selected: _sector == option.key,
                    onTap: () => _setSector(option.key),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (groups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  '这个板块没有可发布的量表结果',
                  style: TextStyle(fontSize: 13, color: DunesColors.text3),
                ),
              )
            else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('kpi-publish-select-all'),
                  onPressed: _selectAll,
                  child: const Text('全选本组'),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final group in groups)
                      _groupTile(
                        group,
                        selected: _selected.contains(group.name),
                      ),
                  ],
                ),
              ),
            ],
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${pending.map((p) => p.userName).where((n) => n.trim().isNotEmpty).take(6).join('、')}'
                '${pending.length > 6 ? ' 等' : ''}共 ${pending.length} 人未评完，这次不发他们。',
                style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const Key('kpi-confirm-ok'),
                    onPressed: scored.isEmpty ? null : _confirm,
                    style: FilledButton.styleFrom(backgroundColor: _accent),
                    child: Text('发布 ${scored.length} 人'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupTile(KpiPublishGroup group, {required bool selected}) {
    return InkWell(
      key: Key('kpi-publish-group-${group.name}'),
      onTap: () => _toggle(group.name),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank,
              size: 22,
              color: selected ? _accent : DunesColors.text3,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                group.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
            ),
            Text(
              '已评 ${group.scored.length} / ${group.expected}',
              style: TextStyle(
                fontSize: 12,
                color: group.pending.isEmpty
                    ? DunesColors.text3
                    : const Color(0xFFB45309),
                fontFeatures: _tabular,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? _accent : const Color(0xFFECE7F4),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : DunesColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}
