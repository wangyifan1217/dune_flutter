import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../contacts/contact_member_picker_page.dart';
import 'proposal_intake_models.dart';
import 'proposal_intake_service.dart';
import 'proposal_intake_ui.dart';

/// 每份提案默认可查看业务成本。服务端按同样的姓名解析账号；这里只用于还没拿到服务端标记的本地草稿。
const kProposalBusinessCostDefaultViewers = ['邓艳丽', '王一凡', '徐峥', '石淼'];

/// 手机上可以点开看名单，不能改权限。电脑端不认这个名单。
const kProposalBusinessCostAccessPeekNames = ['王奕凡', '朱子姝'];

class ProposalBusinessCostAccessDialog extends StatefulWidget {
  const ProposalBusinessCostAccessDialog({
    super.key,
    required this.session,
    required this.service,
    required this.row,
    required this.onUpdated,
    this.readOnly = false,
  });
  final AuthSession session;
  final ProposalIntakeService service;
  final ProposalIntakeRow row;
  final ValueChanged<ProposalIntakeRow> onUpdated;

  /// 只展示名单。添加和开关都不写权限。
  final bool readOnly;

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

  Set<int> get _excludeIds => {
    for (final item in viewers)
      if (int.tryParse('${item['userId']}') case final id?) id,
  };

  Future<void> add() async {
    if (busy) return;
    final picked = await _pickMembers();
    if (!mounted || picked == null || picked.isEmpty) return;
    await update(picked.keys.toList(), true);
  }

  /// 手机和电脑都用居中卡片，和灯塔「谁能看到」一样，不另开整页。
  Future<Map<int, String>?> _pickMembers() {
    final pickerKey = GlobalKey<ContactMemberPickerPanelState>();
    Map<int, String> namesOf(List<int> ids) => {
      for (final id in ids)
        id: pickerKey.currentState?.contactById[id]?.displayName ?? '',
    };
    return showDialog<Map<int, String>>(
      context: context,
      barrierColor: const Color(0xFF241A3D).withAlpha(70),
      builder: (routeContext) {
        final size = MediaQuery.sizeOf(routeContext);
        final width = math.min(420.0, math.max(0.0, size.width - 40));
        final height = math.min(520.0, math.max(0.0, size.height - 72));
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 36,
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Material(
            color: DunesColors.resolve(
              routeContext,
              DunesColors.bgApp,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: width,
              height: height,
              child: ContactMemberPickerPanel(
                key: pickerKey,
                session: widget.session,
                title: '添加可查看人员',
                excludeIds: _excludeIds,
                onCancel: () => Navigator.pop(routeContext),
                onConfirm: (ids) => Navigator.pop(routeContext, namesOf(ids)),
              ),
            ),
          ),
        );
      },
    );
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
    final size = MediaQuery.sizeOf(context);
    // 对话框左右各 16 的外边距、24 的内边距。窄屏按剩余宽度收，避免手机上撑出屏幕。
    final contentWidth = math.min(420.0, math.max(0.0, size.width - 80));
    final contentHeight = (size.height * .48).clamp(240.0, 480.0);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text(
        '业务成本查看权限',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: contentWidth,
        height: contentHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.readOnly) ...[
              Text('最近填写：$editor', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 5),
            ],
            Text(
              widget.readOnly
                  ? '只能查看谁可以看业务成本，不能在这里修改。'
                  : '仅对本提案生效。新增人员可查看本提案，不能因此获得编辑权限。',
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
                if (!widget.readOnly)
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
                      onChanged: widget.readOnly || required || busy || id <= 0
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
