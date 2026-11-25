import 'package:flutter/material.dart';

import '../../core/util/friendly_error.dart';
import 'task_api.dart';
import 'task_helper_picker.dart';
import 'task_models.dart';
import 'task_widgets.dart';

class NativeTaskGoalReportPage extends StatefulWidget {
  const NativeTaskGoalReportPage({super.key, required this.api});

  final TaskApi api;

  @override
  State<NativeTaskGoalReportPage> createState() =>
      _NativeTaskGoalReportPageState();
}

class _NativeTaskGoalReportPageState extends State<NativeTaskGoalReportPage> {
  late DateTimeRange _period;
  TaskAssignee? _owner;
  String? _status;
  int _page = 0;
  int _request = 0;
  bool _loading = true;
  bool _hasMore = false;
  String? _error;
  List<Map> _rows = const [];
  Map _names = const {};
  final _history = <int, Future<Map<String, dynamic>>>{};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _period = DateTimeRange(start: DateTime(now.year, now.month), end: now);
    _load(0);
  }

  Future<void> _load(int page) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _history.clear();
    });
    try {
      final data = await widget.api.goalReportProgress(
        from: _period.start,
        to: _period.end,
        page: page,
        ownerId: _owner?.id,
        status: _status,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _page = page;
        _rows = (data['items'] as List? ?? const []).whereType<Map>().toList();
        _names = data['names'] as Map? ?? const {};
        _hasMore = data['hasMore'] == true;
      });
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = friendlyErrorText(error, fallback: '加载目标进展失败'));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _pickPeriod() async {
    final picked = await showTaskDateRangePicker(
      context,
      initialDateRange: _period,
    );
    if (!mounted || picked == null) return;
    _period = picked;
    await _load(0);
  }

  Future<void> _pickOwner() async {
    final list = await showTaskHelperPicker(
      context,
      api: widget.api,
      selectedIds: const {},
      excludeUserId: 0,
      single: true,
      title: '按目标负责人筛选',
    );
    if (!mounted || list == null || list.isEmpty) return;
    _owner = list.first;
    await _load(0);
  }

  @override
  Widget build(BuildContext context) => TaskTheme(
    child: Scaffold(
      appBar: AppBar(title: const Text('目标进展（日报）')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    label: Text(
                      '${formatTaskYmd(_period.start)} 至 ${formatTaskYmd(_period.end)}',
                    ),
                    onPressed: _pickPeriod,
                  ),
                  ActionChip(
                    label: Text(_owner?.displayName ?? '全部负责人'),
                    onPressed: _pickOwner,
                  ),
                  if (_owner != null)
                    ActionChip(
                      label: const Text('清除负责人'),
                      onPressed: () {
                        _owner = null;
                        _load(0);
                      },
                    ),
                  TaskFilterChipDropdown<String?>(
                    value: _status,
                    label: _status == null
                        ? '全部状态'
                        : (_status == 'completed' ? '已完成' : '进行中'),
                    items: const [
                      (null, '全部状态'),
                      ('active_or_in_progress', '进行中'),
                      ('completed', '已完成'),
                    ],
                    onChanged: (value) {
                      _status = value;
                      _load(0);
                    },
                  ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (!_loading && _error != null)
              TextButton(
                onPressed: () => _load(_page),
                child: Text('$_error，点击重试'),
              ),
            if (!_loading && _error == null)
              Expanded(
                child: _rows.isEmpty
                    ? const Center(child: Text('所选范围内暂无已提交的目标进展'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: _rows.length + 1,
                        itemBuilder: (_, i) =>
                            i == _rows.length ? _pagination() : _goal(_rows[i]),
                      ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _pagination() => Wrap(
    alignment: WrapAlignment.end,
    spacing: 8,
    children: [
      if (_page > 0)
        TextButton(onPressed: () => _load(_page - 1), child: const Text('上一页')),
      if (_hasMore)
        TextButton(onPressed: () => _load(_page + 1), child: const Text('下一页')),
    ],
  );

  Widget _goal(Map row) {
    final id = (row['goalId'] as num).toInt();
    final owner = _names['${row['ownerId']}'] ?? '—';
    final progress = row['progress'] ?? 0;
    final submittedAt = DateTime.tryParse('${row['submittedAt'] ?? ''}')
        ?.toUtc()
        .add(const Duration(hours: 8));
    final date = submittedAt == null
        ? row['reportDate'] ?? '—'
        : submittedAt.toIso8601String().substring(0, 16).replaceFirst('T', ' ');
    final blockers = '${row['blockers'] ?? ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        key: ValueKey(id),
        title: Text(
          '${row['title'] ?? ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$owner · $progress% · 最近更新 $date'),
            Text(
              '${row['workDone'] ?? ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (blockers.isNotEmpty)
              Text(
                '阻塞 $blockers',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        onExpansionChanged: (open) {
          if (open && !_history.containsKey(id)) {
            final request = widget.api.goalReportProgress(
              from: _period.start,
              to: _period.end,
              goalId: id,
            );
            setState(() {
              _history[id] = request;
            });
          }
        },
        children: [if (_history[id] != null) _historyPage(id, _history[id]!)],
      ),
    );
  }

  Widget _historyPage(
    int id,
    Future<Map<String, dynamic>> future, {
    int page = 0,
  }) => FutureBuilder<Map<String, dynamic>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const ListTile(title: Text('加载日报记录失败'));
      final data = snapshot.data;
      if (data == null) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(),
        );
      }
      final names = data['names'] as Map? ?? const {};
      final items = (data['items'] as List? ?? const []).whereType<Map>();
      return Column(
        children: [
          for (final record in items)
            ListTile(
              dense: true,
              title: Text(
                '${record['reportDate']} · ${names['${record['reporterId']}'] ?? '—'} · ${record['taskId'] == id ? '主任务' : '子任务 ${record['taskTitle']}'}',
              ),
              subtitle: Text('${record['workDone'] ?? ''}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openReport(record),
            ),
          if (data['hasMore'] == true)
            TextButton(
              onPressed: () => _showMoreHistory(id, page + 1),
              child: const Text('查看更多记录'),
            ),
        ],
      );
    },
  );

  Future<void> _showMoreHistory(int id, int page) {
    final next = widget.api.goalReportProgress(
      from: _period.start,
      to: _period.end,
      goalId: id,
      page: page,
    );
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('目标日报记录'),
        content: SizedBox(
          width: 520,
          child: _historyPage(id, next, page: page),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _openReport(Map record) async {
    final request = widget.api.getDailyReport(
      date: DateTime.tryParse('${record['reportDate']}'),
      userId: (record['reporterId'] as num).toInt(),
    );
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: Text('${record['reportDate']} 日报'),
        content: SizedBox(
          width: 520,
          child: FutureBuilder<TaskDailyReportBundle>(
            future: request,
            builder: (_, snapshot) {
              if (snapshot.hasError) return const Text('无法查看该日报');
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final report = snapshot.data?.report;
              if (report == null) return const Text('暂无日报');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in report.items)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.taskTitle),
                      subtitle: Text(item.workDone),
                    ),
                  if (report.summary.isNotEmpty) Text('其他工作 ${report.summary}'),
                  if (report.blockers.isNotEmpty) Text('阻塞 ${report.blockers}'),
                  if (report.nextPlan.isNotEmpty)
                    Text('明日计划 ${report.nextPlan}'),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
