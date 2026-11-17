import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../contacts/contact_member_picker_page.dart';
import 'proposal_intake_models.dart';
import 'proposal_intake_service.dart';
import 'proposal_intake_ui.dart';

class ProposalBusinessCostAccessDialog extends StatefulWidget {
  const ProposalBusinessCostAccessDialog({
    super.key,
    required this.session,
    required this.service,
    required this.row,
    required this.onUpdated,
  });
  final AuthSession session;
  final ProposalIntakeService service;
  final ProposalIntakeRow row;
  final ValueChanged<ProposalIntakeRow> onUpdated;

  @override
  State<ProposalBusinessCostAccessDialog> createState() =>
      _ProposalBusinessCostAccessDialogState();
}

class _ProposalBusinessCostAccessDialogState
    extends State<ProposalBusinessCostAccessDialog> {
  late ProposalIntakeRow row = widget.row;
  bool busy = false;
  String error = '';
  Map<String, dynamic> get info => row.form['businessCostAccessInfo'] is Map
      ? Map<String, dynamic>.from(row.form['businessCostAccessInfo'] as Map)
      : {};
  List<Map<String, dynamic>> get viewers => [
    for (final entry
        in info['viewers'] is List ? info['viewers'] as List : const [])
      if (entry is Map) Map<String, dynamic>.from(entry),
  ];

  Future<void> update(List<int> ids, bool enabled) async {
    if (ids.isEmpty || busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final updated = await widget.service.setBusinessCostViewers(
        row.id,
        ids,
        enabled: enabled,
      );
      if (!mounted) return;
      setState(() => row = updated);
      widget.onUpdated(updated);
    } catch (e) {
      if (mounted) setState(() => error = friendlyErrorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> add() async {
    if (busy) return;
    final exclude = <int>{
      for (final item in viewers)
        if (int.tryParse('${item['userId']}') case final id?) id,
    };
    final ids = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(
        builder: (_) => ContactMemberPickerPage(
          session: widget.session,
          title: '添加可查看人员',
          excludeIds: exclude,
        ),
      ),
    );
    if (mounted && ids != null && ids.isNotEmpty) await update(ids, true);
  }

  @override
  Widget build(BuildContext context) {
    final accent = DunesColors.resolve(context, ProposalPalette.purple);
    final muted = DunesColors.resolve(context, ProposalPalette.text3);
    final editorId = '${info['lastEditorUserId'] ?? ''}'.trim();
    final editorName = '${info['lastEditorName'] ?? ''}'.trim();
    final editor = editorName.isNotEmpty
        ? editorName
        : editorId.isNotEmpty && editorId != 'null' && editorId != '0'
        ? '用户$editorId'
        : '历史记录未记录';
    final rows = viewers;
    return AlertDialog(
      title: const Text(
        '业务成本查看权限',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 420,
        height: MediaQuery.sizeOf(context).height * .48,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('最近填写：$editor', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 5),
            Text(
              '仅对本提案生效。新增人员可查看本提案，不能因此获得编辑权限。',
              style: TextStyle(fontSize: 12, height: 1.4, color: muted),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '查看人员',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: busy ? null : add,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加'),
                  style: TextButton.styleFrom(
                    foregroundColor: accent,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            if (error.isNotEmpty)
              Text(
                error,
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolve(context, ProposalPalette.coral),
                ),
              ),
            if (busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final item = rows[index];
                  final id = int.tryParse('${item['userId']}') ?? 0;
                  final name = '${item['name'] ?? ''}'.trim();
                  final role = '${item['role'] ?? ''}'.trim();
                  final required = item['required'] == true;
                  final enabled = item['enabled'] == true;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      name.isEmpty ? '用户$id' : name,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      required
                          ? '$role · 必要权限'
                          : enabled
                          ? '可查看'
                          : '已关闭',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                    trailing: Switch(
                      value: enabled,
                      activeColor: accent,
                      onChanged: required || busy || id <= 0
                          ? null
                          : (v) => update([id], v),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
