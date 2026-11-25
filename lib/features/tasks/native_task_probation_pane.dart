import 'package:flutter/material.dart';

import '../../core/util/friendly_error.dart';
import '../shell/dunes_toast.dart';
import 'task_management_api.dart';
import 'task_widgets.dart';

class NativeTaskProbationPane extends StatefulWidget {
  const NativeTaskProbationPane({
    super.key,
    required this.api,
    required this.onImport,
  });

  final TaskManagementApi api;
  final VoidCallback onImport;

  @override
  State<NativeTaskProbationPane> createState() =>
      _NativeTaskProbationPaneState();
}

class _NativeTaskProbationPaneState extends State<NativeTaskProbationPane> {
  final _query = TextEditingController();
  String _department = '';
  List<String> _departments = const [];
  List<Map> _people = const [];
  int _page = 0;
  int _total = 0;
  int _request = 0;
  bool _hasMore = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(0);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load(int page) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.listProbationGoals(
        query: _query.text.trim(),
        department: _department,
        page: page,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _page = page;
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _people = (data['items'] as List? ?? const [])
            .whereType<Map>()
            .toList();
        _departments = (data['departments'] as List? ?? const [])
            .whereType<String>()
            .toList();
        _hasMore = data['hasMore'] == true;
      });
    } catch (error) {
      if (mounted && request == _request) {
        setState(
          () => _error = friendlyErrorText(error, fallback: '加载试用期目标失败'),
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _assign(Map person) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _AssignProbationGoalDialog(api: widget.api, person: person),
    );
    if (ok == true && mounted) {
      showDunesCenterToast(context, '试用期目标已指派');
      await _load(_page);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TaskTheme(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _load(0),
                  decoration: const InputDecoration(
                    hintText: '姓名、员工编号或部门',
                    isDense: true,
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: () => _load(0),
                child: const Text('搜索'),
              ),
              PopupMenuButton<String>(
                tooltip: '按部门筛选',
                onSelected: (value) {
                  setState(() => _department = value);
                  _load(0);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: '', child: Text('全部部门')),
                  for (final department in _departments)
                    PopupMenuItem(value: department, child: Text(department)),
                ],
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _department.isEmpty ? '全部部门 ▾' : '$_department ▾',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: widget.onImport,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('批量导入'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            TextButton(
              onPressed: () => _load(_page),
              child: Text('$_error，点击重试'),
            ),
          if (!_loading && _error == null) ...[
            Text(_total == 0 ? '暂无符合条件的试用期员工' : '共 $_total 人'),
            for (final person in _people) _employeeCard(person),
            if (_page > 0 || _hasMore)
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _page > 0 ? () => _load(_page - 1) : null,
                    child: const Text('上一页'),
                  ),
                  TextButton(
                    onPressed: _hasMore ? () => _load(_page + 1) : null,
                    child: const Text('下一页'),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _employeeCard(Map person) {
    final summary = person['summary'] as Map? ?? const {};
    final progress = ((summary['progress'] as num?)?.toInt() ?? 0).clamp(
      0,
      100,
    );
    final total = summary['total'] ?? 0;
    final updated = '${summary['updatedAt'] ?? ''}';
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${person['name'] ?? ''} · ${person['department'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => _assign(person),
                  child: const Text('指派目标'),
                ),
              ],
            ),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text('试用期截止 ${person['probationEndAt'] ?? '—'}'),
                Text(
                  total == 0
                      ? '尚未指派目标'
                      : '已完成 ${summary['completed'] ?? 0} / $total · $progress%',
                ),
                if (updated.isNotEmpty) Text('最近更新 $updated'),
              ],
            ),
            if (total != 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress / 100),
            ],
          ],
        ),
      ),
    );
  }
}

class _AssignProbationGoalDialog extends StatefulWidget {
  const _AssignProbationGoalDialog({required this.api, required this.person});

  final TaskManagementApi api;
  final Map person;

  @override
  State<_AssignProbationGoalDialog> createState() =>
      _AssignProbationGoalDialogState();
}

class _AssignProbationGoalDialogState
    extends State<_AssignProbationGoalDialog> {
  final _title = TextEditingController();
  final _criteria = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _criteria.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _criteria.text.trim().isEmpty) {
      setState(() => _error = '请填写目标名称和验收标准');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.assignProbationGoal(
        (widget.person['userId'] as num).toInt(),
        _title.text.trim(),
        _criteria.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyErrorText(error, fallback: '指派失败');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => TaskTheme(
    child: AlertDialog(
      scrollable: true,
      title: Text('指派试用期目标 · ${widget.person['name'] ?? ''}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              maxLength: 80,
              decoration: const InputDecoration(labelText: '目标名称'),
            ),
            TextField(
              controller: _criteria,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '验收标准'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? '正在指派…' : '确认指派'),
        ),
      ],
    ),
  );
}
