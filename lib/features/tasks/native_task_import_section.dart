import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'task_avatar.dart';
import 'task_management_api.dart';
import 'task_widgets.dart';

ButtonStyle taskImportFilledStyle() {
  return FilledButton.styleFrom(
    backgroundColor: kTaskPurple,
    foregroundColor: Colors.white,
    disabledBackgroundColor: kTaskPurple.withValues(alpha: 0.35),
  );
}

class TaskImportKindTabs extends StatelessWidget {
  const TaskImportKindTabs({
    super.key,
    required this.kind,
    required this.onChanged,
  });

  final String kind;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _KindChip(
          label: '任务模板',
          selected: kind == 'task',
          onTap: () => onChanged('task'),
        ),
        _KindChip(
          label: '试用期任务模板',
          selected: kind == 'probation',
          onTap: () => onChanged('probation'),
        ),
      ],
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kTaskPurple : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? kTaskPurple : const Color(0xFFE8EAED),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : DunesColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

class TaskImportDropZone extends StatelessWidget {
  const TaskImportDropZone({
    super.key,
    required this.fileName,
    required this.dragging,
    required this.onPick,
    this.busy = false,
  });

  final String? fileName;
  final bool dragging;
  final bool busy;
  final VoidCallback onPick;

  bool get _supportsDesktopDrop {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  Widget build(BuildContext context) {
    final selected = fileName != null && fileName!.trim().isNotEmpty;
    final hint = busy
        ? '处理中…'
        : selected
        ? fileName!
        : (_supportsDesktopDrop || isDesktopCommOnly
              ? '点击选择，或拖拽 Excel 到此处'
              : '点击选择 Excel 文件');
    return Material(
      color: dragging ? kTaskPurple.withValues(alpha: 0.08) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: busy ? null : onPick,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: dragging
                  ? kTaskPurple.withValues(alpha: 0.45)
                  : const Color(0xFFE8EAED),
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.table_chart_outlined
                    : Icons.upload_file_outlined,
                color: dragging || selected ? kTaskPurple : DunesColors.text3,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: dragging ? kTaskPurple : DunesColors.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      '支持 .xlsx / .csv · 导入前会预览校验，不会直接修改现有任务',
                      style: TextStyle(fontSize: 11, color: DunesColors.text3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TaskImportPreviewStats extends StatelessWidget {
  const TaskImportPreviewStats({super.key, required this.preview});

  final TaskImportPreview preview;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(label: '总行数', value: '${preview.total}'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: '可导入',
            value: '${preview.valid}',
            color: const Color(0xFF15803D),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: '错误',
            value: '${preview.invalid}',
            color: preview.invalid > 0 ? const Color(0xFFBE123C) : null,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color ?? DunesColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: DunesColors.text3),
          ),
        ],
      ),
    );
  }
}

class TaskImportEmployeeCard extends StatelessWidget {
  const TaskImportEmployeeCard({
    super.key,
    required this.session,
    required this.employee,
    required this.onPick,
  });

  final AuthSession session;
  final TaskImportEmployee? employee;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final selected = employee;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPick,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE8EAED)),
          ),
          child: Row(
            children: [
              if (selected != null)
                buildTaskUserAvatar(
                  session: session,
                  name: selected.displayName,
                  userId: selected.id,
                  avatarPreset: selected.avatarPreset,
                  avatarObjectKey: selected.avatarObjectKey,
                  avatarUrl: selected.avatarUrl,
                  size: 36,
                )
              else
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(0xFFF3EEFA),
                  child: Icon(Icons.person_outline, color: kTaskPurple),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected?.displayName.isNotEmpty == true
                          ? selected!.displayName
                          : '选择试用期员工',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selected == null
                          ? '导入前先选定一名新员工，系统会读取入职日和试用期结束日'
                          : [
                              if (selected.departmentName.isNotEmpty)
                                selected.departmentName,
                              if (selected.periodLabel.isNotEmpty)
                                '试用期 ${selected.periodLabel}',
                            ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: DunesColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                selected == null ? '选择' : '更换',
                style: const TextStyle(
                  color: kTaskPurple,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<TaskImportEmployee?> showTaskImportEmployeePicker(
  BuildContext context, {
  required AuthSession session,
  required Future<List<TaskImportEmployee>> Function(String q) search,
}) {
  return showDialog<TaskImportEmployee>(
    context: context,
    builder: (ctx) =>
        _TaskImportEmployeeDialog(session: session, search: search),
  );
}

class _TaskImportEmployeeDialog extends StatefulWidget {
  const _TaskImportEmployeeDialog({
    required this.session,
    required this.search,
  });

  final AuthSession session;
  final Future<List<TaskImportEmployee>> Function(String q) search;

  @override
  State<_TaskImportEmployeeDialog> createState() =>
      _TaskImportEmployeeDialogState();
}

class _TaskImportEmployeeDialogState extends State<_TaskImportEmployeeDialog> {
  final _searchCtrl = TextEditingController();
  List<TaskImportEmployee> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load(''));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.search(q);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('选择试用期员工'),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              onSubmitted: (v) => unawaited(_load(v.trim())),
              decoration: InputDecoration(
                hintText: '搜索姓名、手机号或工号',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: IconButton(
                  onPressed: () => unawaited(_load(_searchCtrl.text.trim())),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                ),
                filled: true,
                fillColor: const Color(0xFFF5F6F8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6F8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: kTaskPurple),
                      )
                    : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFFE35D6A)),
                        ),
                      )
                    : _items.isEmpty
                    ? const Center(
                        child: Text(
                          '没有匹配的员工',
                          style: TextStyle(color: DunesColors.text3),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final item = _items[i];
                          return ListTile(
                            leading: buildTaskUserAvatar(
                              session: widget.session,
                              name: item.displayName,
                              userId: item.id,
                              avatarPreset: item.avatarPreset,
                              avatarObjectKey: item.avatarObjectKey,
                              avatarUrl: item.avatarUrl,
                              size: 36,
                            ),
                            title: Text(item.displayName),
                            subtitle: Text(
                              [
                                if (item.departmentName.isNotEmpty)
                                  item.departmentName,
                                if (item.periodLabel.isNotEmpty)
                                  item.periodLabel,
                              ].join(' · '),
                            ),
                            onTap: () => Navigator.pop(context, item),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class TaskImportDropHost extends StatelessWidget {
  const TaskImportDropHost({
    super.key,
    required this.enabled,
    required this.onDragging,
    required this.onDropped,
    required this.child,
  });

  final bool enabled;
  final ValueChanged<bool> onDragging;
  final ValueChanged<List<DropItem>> onDropped;
  final Widget child;

  bool get _supportsDesktopDrop {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  Widget build(BuildContext context) {
    if (!_supportsDesktopDrop) return child;
    return DropTarget(
      enable: enabled && desktopDropLive(context),
      onDragEntered: (_) => onDragging(true),
      onDragExited: (_) => onDragging(false),
      onDragDone: (detail) {
        onDragging(false);
        onDropped(detail.files);
      },
      child: child,
    );
  }
}
