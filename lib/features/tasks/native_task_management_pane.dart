import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'native_task_hrbp_pane.dart';
import 'task_api.dart';
import 'task_management_api.dart';
import 'task_models.dart';
import 'task_recurring_create_dialog.dart';
import 'task_widgets.dart';

enum TaskManagementSection {
  home,
  pending,
  recurring,
  team,
  config,
  calendar,
  import,
  history,
}

class NativeTaskManagementPane extends StatefulWidget {
  const NativeTaskManagementPane({
    super.key,
    required this.session,
    required this.onBack,
    this.onOpenTask,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final ValueChanged<int>? onOpenTask;

  @override
  State<NativeTaskManagementPane> createState() =>
      _NativeTaskManagementPaneState();
}

class _NativeTaskManagementPaneState extends State<NativeTaskManagementPane> {
  late final TaskApi _taskApi = TaskApi(widget.session);
  late final TaskManagementApi _managementApi = TaskManagementApi(
    widget.session,
  );

  TaskManagementSection _section = TaskManagementSection.home;
  List<TaskItem> _pendingTasks = const [];
  List<TaskRecurringRule> _rules = const [];
  List<TaskImportHistoryItem> _history = const [];
  List<TaskCalendarDay> _calendarDays = const [];
  String? _error;
  bool _loading = false;
  bool _saving = false;
  bool _syncingCalendar = false;

  bool _reportReminderEnabled = true;
  bool _recurringTaskEnabled = true;
  bool _taskApprovalEnabled = true;
  bool _assignmentConfirmationEnabled = false;
  final _firstReminderController = TextEditingController(text: '18:10');
  final _deadlineController = TextEditingController(text: '22:00');
  final _calendarYearController = TextEditingController(
    text: '${DateTime.now().year}',
  );
  String _calendarFilter = 'all';

  String? _selectedFileName;
  Uint8List? _selectedFileBytes;
  String _importKind = 'task';
  TaskImportPreview? _preview;
  bool _previewing = false;
  bool _committing = false;

  bool get _canPending => widget.session.taskPendingAccess;

  bool get _canTeam => widget.session.taskTeamSummaryAccess;

  bool get _canRecurring => widget.session.taskRecurringAccess;

  bool get _canConfig => widget.session.taskConfigAccess;

  bool get _canCalendar => widget.session.taskCalendarAccess;

  bool get _canImport => widget.session.taskImportAccess;

  bool get _canHistory => widget.session.taskImportHistoryAccess;

  @override
  void dispose() {
    _firstReminderController.dispose();
    _deadlineController.dispose();
    _calendarYearController.dispose();
    super.dispose();
  }

  String get _title => switch (_section) {
    TaskManagementSection.home => '任务功能',
    TaskManagementSection.pending => '待我处理',
    TaskManagementSection.recurring => '周期任务',
    TaskManagementSection.team => '团队任务汇总',
    TaskManagementSection.config => '任务配置',
    TaskManagementSection.calendar => '节假日日历',
    TaskManagementSection.import => '任务导入',
    TaskManagementSection.history => '导入记录',
  };

  void _select(TaskManagementSection section) {
    if (section == TaskManagementSection.pending && !_canPending) return;
    if (section == TaskManagementSection.team && !_canTeam) return;
    if (section == TaskManagementSection.recurring && !_canRecurring) return;
    if (section == TaskManagementSection.config && !_canConfig) return;
    if (section == TaskManagementSection.calendar && !_canCalendar) return;
    if (section == TaskManagementSection.import && !_canImport) return;
    if (section == TaskManagementSection.history && !_canHistory) return;
    setState(() {
      _section = section;
      _error = null;
      _preview = null;
    });
    switch (section) {
      case TaskManagementSection.pending:
        unawaited(_loadPending());
      case TaskManagementSection.recurring:
        unawaited(_loadRules());
      case TaskManagementSection.config:
        unawaited(_loadConfig());
      case TaskManagementSection.calendar:
        unawaited(_loadCalendar());
      case TaskManagementSection.history:
        unawaited(_loadHistory());
      case TaskManagementSection.home:
      case TaskManagementSection.team:
      case TaskManagementSection.import:
        break;
    }
  }

  Future<void> _loadPending() async {
    setState(() => _loading = true);
    try {
      final page = await _taskApi.listTasksPage(
        scope: 'pending_actions',
        size: 100,
      );
      if (!mounted) return;
      setState(() {
        _pendingTasks = page.items;
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

  Future<void> _loadRules() async {
    setState(() => _loading = true);
    try {
      final rules = await _managementApi.listRecurringRules();
      if (!mounted) return;
      setState(() {
        _rules = rules;
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

  Future<void> _loadConfig() async {
    setState(() => _loading = true);
    try {
      final config = await _managementApi.getConfig();
      if (!mounted) return;
      _applyConfig(config);
      setState(() {
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

  Future<void> _loadCalendar() async {
    setState(() => _loading = true);
    try {
      final year = int.tryParse(_calendarYearController.text.trim());
      final snapshot = await _managementApi.listTaskCalendar(year: year);
      if (!mounted) return;
      setState(() {
        if (snapshot.year > 0) {
          _calendarYearController.text = '${snapshot.year}';
        }
        _calendarDays = snapshot.items;
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

  Future<void> _syncCalendar() async {
    final year = int.tryParse(_calendarYearController.text.trim());
    if (year == null || year < 2000 || year > 2200) {
      _showMessage('请输入正确的年份', error: true);
      return;
    }
    setState(() {
      _syncingCalendar = true;
      _error = null;
    });
    try {
      final result = await _managementApi.syncTaskCalendar(year: year);
      if (!mounted) return;
      _showMessage('已同步 ${result.year == 0 ? year : result.year} 年节假日');
      await _loadCalendar();
    } catch (e) {
      if (mounted) _showMessage('同步节假日失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _syncingCalendar = false);
    }
  }

  void _applyConfig(Map<String, dynamic> config) {
    _reportReminderEnabled = config['dailyReportReminderEnabled'] != false;
    _recurringTaskEnabled = config['recurringTaskEnabled'] != false;
    _taskApprovalEnabled = config['taskApprovalEnabled'] != false;
    _assignmentConfirmationEnabled =
        config['assignmentConfirmationEnabled'] == true;
    final first = '${config['firstReminderAt'] ?? '18:10'}';
    final deadline = '${config['reportDeadlineAt'] ?? '22:00'}';
    _firstReminderController.text = first;
    _deadlineController.text = deadline;
  }

  Future<void> _saveConfig() async {
    setState(() => _saving = true);
    try {
      final result = await _managementApi.saveConfig({
        'dailyReportReminderEnabled': _reportReminderEnabled,
        'recurringTaskEnabled': _recurringTaskEnabled,
        'taskApprovalEnabled': _taskApprovalEnabled,
        'assignmentConfirmationEnabled': _assignmentConfirmationEnabled,
        'firstReminderAt': _firstReminderController.text.trim(),
        'reportDeadlineAt': _deadlineController.text.trim(),
      });
      if (!mounted) return;
      _applyConfig(result);
      setState(() {
        _saving = false;
      });
      _showMessage('任务配置已保存');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('保存失败：$e', error: true);
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    try {
      final history = await _managementApi.listImportHistory();
      if (!mounted) return;
      setState(() {
        _history = history;
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

  Future<void> _pickImportFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Excel/CSV', extensions: ['xlsx', 'csv']),
      ],
    );
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedFileName = file.name;
        _selectedFileBytes = bytes;
        _preview = null;
        _error = null;
      });
    } catch (e) {
      if (mounted) _showMessage('读取文件失败：$e', error: true);
    }
  }

  Future<void> _previewImport() async {
    final bytes = _selectedFileBytes;
    final fileName = _selectedFileName;
    if (bytes == null || fileName == null) {
      _showMessage('请先选择 Excel 文件', error: true);
      return;
    }
    setState(() {
      _previewing = true;
      _error = null;
    });
    try {
      final preview = await _managementApi.previewImport(
        bytes: bytes,
        fileName: fileName,
        importKind: _importKind,
      );
      if (!mounted) return;
      setState(() => _preview = preview);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _commitImport() async {
    final importId = _preview?.importId.trim() ?? '';
    if (importId.isEmpty) {
      _showMessage('当前预览结果不可提交', error: true);
      return;
    }
    setState(() => _committing = true);
    try {
      await _managementApi.commitImport(importId);
      if (!mounted) return;
      setState(() {
        _committing = false;
        _selectedFileName = null;
        _selectedFileBytes = null;
        _preview = null;
      });
      _showMessage('导入任务已提交');
    } catch (e) {
      if (!mounted) return;
      setState(() => _committing = false);
      _showMessage('提交导入失败：$e', error: true);
    }
  }

  Future<void> _createRule() async {
    final draft = await showTaskRecurringCreateDialog(context);
    if (draft == null || !mounted) return;
    try {
      await _managementApi.createRecurringRule({
        'title': draft.title,
        'frequency': draft.frequency,
        'startDate': draft.startDate,
        'endDate': draft.endDate,
      });
      if (mounted) {
        _showMessage('周期任务已创建');
        unawaited(_loadRules());
      }
    } catch (e) {
      if (mounted) _showMessage('创建失败：$e', error: true);
    }
  }

  Future<void> _toggleRule(TaskRecurringRule rule) async {
    try {
      await _managementApi.setRecurringRuleEnabled(rule.id, !rule.enabled);
      if (!mounted) return;
      _showMessage(rule.enabled ? '周期规则已停用' : '周期规则已启用');
      unawaited(_loadRules());
    } catch (e) {
      if (mounted) _showMessage('更新周期规则失败：$e', error: true);
    }
  }

  Future<void> _executeRule(TaskRecurringRule rule) async {
    try {
      final execution = await _managementApi.executeRecurringRule(rule.id);
      if (!mounted) return;
      _showMessage(
        execution.status == 'success' ? '周期任务已生成' : '周期任务执行失败',
        error: execution.status != 'success',
      );
      unawaited(_loadRules());
    } catch (e) {
      if (mounted) _showMessage('执行周期任务失败：$e', error: true);
    }
  }

  Future<void> _showRuleExecutions(TaskRecurringRule rule) async {
    try {
      final executions = await _managementApi.listRecurringExecutions(rule.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${rule.title} · 执行记录'),
          content: SizedBox(
            width: 460,
            child: executions.isEmpty
                ? const Text('暂无执行记录')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: executions.length,
                    itemBuilder: (context, index) {
                      final item = executions[index];
                      return ListTile(
                        dense: true,
                        title: Text(item.scheduledDate),
                        subtitle: Text(item.errorMessage),
                        trailing: Text(item.status),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _showMessage('读取执行记录失败：$e', error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    showDunesCenterToast(
      context,
      message,
      kind: error ? DunesToastKind.error : DunesToastKind.normal,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            tooltip: '返回任务',
            onPressed: _section == TaskManagementSection.home
                ? widget.onBack
                : () => _select(TaskManagementSection.home),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          ),
          const SizedBox(width: 4),
          Text(
            _title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          if (_section == TaskManagementSection.pending)
            IconButton(
              tooltip: '刷新',
              onPressed: () => unawaited(_loadPending()),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_section == TaskManagementSection.home) return _buildHome();
    if (_section == TaskManagementSection.team) {
      return NativeTaskHrbpPane(session: widget.session);
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kTaskPurple));
    }
    if (_error != null) {
      return _buildError(_error!, onRetry: _retryCurrentSection);
    }
    return switch (_section) {
      TaskManagementSection.pending => _buildPending(),
      TaskManagementSection.recurring => _buildRecurring(),
      TaskManagementSection.config => _buildConfig(),
      TaskManagementSection.calendar => _buildCalendar(),
      TaskManagementSection.import => _buildImport(),
      TaskManagementSection.history => _buildHistory(),
      TaskManagementSection.home => _buildHome(),
      TaskManagementSection.team => const SizedBox.shrink(),
    };
  }

  void _retryCurrentSection() {
    switch (_section) {
      case TaskManagementSection.pending:
        unawaited(_loadPending());
      case TaskManagementSection.recurring:
        unawaited(_loadRules());
      case TaskManagementSection.config:
        unawaited(_loadConfig());
      case TaskManagementSection.calendar:
        unawaited(_loadCalendar());
      case TaskManagementSection.history:
        unawaited(_loadHistory());
      case TaskManagementSection.home:
      case TaskManagementSection.team:
      case TaskManagementSection.import:
        break;
    }
  }

  Widget _buildHome() {
    final cards = <Widget>[];
    if (_canPending) {
      cards.add(
        _sectionCard(
          icon: Icons.pending_actions_outlined,
          title: '待我处理',
          subtitle: '任务变更审批、指派确认和待办操作',
          onTap: () => _select(TaskManagementSection.pending),
        ),
      );
    }
    if (_canRecurring) {
      cards.add(
        _sectionCard(
          icon: Icons.repeat_rounded,
          title: '周期任务',
          subtitle: '维护周期规则和执行范围',
          onTap: () => _select(TaskManagementSection.recurring),
        ),
      );
    }
    if (_canConfig) {
      cards.add(
        _sectionCard(
          icon: Icons.settings_outlined,
          title: '任务配置',
          subtitle: '日报提醒、审批和周期任务规则',
          onTap: () => _select(TaskManagementSection.config),
        ),
      );
    }
    if (_canCalendar) {
      cards.add(
        _sectionCard(
          icon: Icons.event_available_outlined,
          title: '节假日日历',
          subtitle: '同步法定节假日和调休上班日，供任务日报使用',
          onTap: () => _select(TaskManagementSection.calendar),
        ),
      );
    }
    if (_canImport) {
      cards.add(
        _sectionCard(
          icon: Icons.file_upload_outlined,
          title: '任务导入',
          subtitle: '任务或试用期任务批量导入',
          onTap: () => _select(TaskManagementSection.import),
        ),
      );
    }
    if (_canHistory) {
      cards.add(
        _sectionCard(
          icon: Icons.history_rounded,
          title: '导入记录',
          subtitle: '查看导入文件、状态和结果',
          onTap: () => _select(TaskManagementSection.history),
        ),
      );
    }
    if (_canTeam) {
      cards.insert(
        cards.isEmpty ? 0 : 1,
        _sectionCard(
          icon: Icons.groups_outlined,
          title: '团队任务汇总',
          subtitle: '部门任务进度和日报完成情况',
          onTap: () => _select(TaskManagementSection.team),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      children: [
        const Text(
          '仅展示任务相关的管理和待办功能，不改变原有任务列表、详情和日报流程。',
          style: TextStyle(fontSize: 13, color: DunesColors.text3, height: 1.4),
        ),
        const SizedBox(height: 14),
        ...cards,
      ],
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: kTaskPurple.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: kTaskPurple),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: DunesColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: DunesColors.text3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPending() {
    if (_pendingTasks.isEmpty) {
      return _emptyState(
        Icons.task_alt_outlined,
        '暂无待处理任务',
        '任务审批、修改待审批和指派确认会显示在这里。',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      itemCount: _pendingTasks.length,
      itemBuilder: (context, index) {
        final task = _pendingTasks[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          child: ListTile(
            title: Text(
              task.title.isEmpty ? '未命名任务' : task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [
                if (task.ownerName.isNotEmpty) '负责人 ${task.ownerName}',
                if (task.hasPendingChange)
                  taskPendingChangeLabel(task.pendingChangeKind)
                else
                  taskStatusLabel(task.status),
              ].join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onOpenTask == null
                ? null
                : () => widget.onOpenTask!(task.id),
          ),
        );
      },
    );
  }

  Widget _buildRecurring() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '到达周期后自动生成主目标，可随时停用。',
                  style: TextStyle(
                    fontSize: 13,
                    color: DunesColors.text3,
                    height: 1.35,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _createRule,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建周期任务'),
                style: FilledButton.styleFrom(
                  backgroundColor: kTaskPurple,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _rules.isEmpty
              ? _emptyState(
                  Icons.repeat_rounded,
                  '暂无周期任务',
                  '创建后将在下一周期生成任务。',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  itemCount: _rules.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ruleCard(_rules[i]),
                ),
        ),
      ],
    );
  }

  String _ruleRangeLabel(TaskRecurringRule rule) {
    if (rule.startDate.isEmpty && rule.endDate.isEmpty) return '未设置有效期';
    if (rule.startDate.isNotEmpty && rule.endDate.isEmpty) {
      return '${rule.startDate} 起 · 长期有效';
    }
    if (rule.startDate.isEmpty) return '至 ${rule.endDate}';
    return '${rule.startDate}  ~  ${rule.endDate}';
  }

  Widget _ruleMenuItem({
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final tone = color ?? DunesColors.text;
    return Row(
      children: [
        Icon(icon, size: 18, color: tone),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: tone,
          ),
        ),
      ],
    );
  }

  Widget _ruleCard(TaskRecurringRule rule) {
    final enabled = rule.enabled;
    final accent = enabled ? kTaskPurple : const Color(0xFF9AA0A6);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE3E5EA)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 42,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.title.isEmpty ? '未命名周期任务' : rule.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: DunesColors.text,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      TaskMetaChip(
                        text: taskRecurringFrequencyLabel(rule.frequency),
                        color: kTaskPurple,
                      ),
                      TaskMetaChip(
                        text: _ruleRangeLabel(rule),
                        color: DunesColors.text2,
                      ),
                      if (rule.ownerName.isNotEmpty)
                        TaskMetaChip(
                          text: rule.ownerName,
                          color: const Color(0xFF3D7A8C),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _statusPill(enabled ? '启用中' : '已停用', enabled),
                const SizedBox(height: 4),
                PopupMenuButton<String>(
                  tooltip: '更多操作',
                  offset: const Offset(0, 8),
                  position: PopupMenuPosition.under,
                  color: Colors.white,
                  surfaceTintColor: Colors.white,
                  elevation: 6,
                  shadowColor: Colors.black.withValues(alpha: 0.08),
                  constraints: const BoxConstraints(minWidth: 176),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFE8EAED)),
                  ),
                  onSelected: (value) {
                    if (value == 'toggle') unawaited(_toggleRule(rule));
                    if (value == 'execute') unawaited(_executeRule(rule));
                    if (value == 'history') unawaited(_showRuleExecutions(rule));
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'execute',
                      height: 44,
                      child: _ruleMenuItem(
                        icon: Icons.play_arrow_rounded,
                        label: '立即生成',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'history',
                      height: 44,
                      child: _ruleMenuItem(
                        icon: Icons.history_rounded,
                        label: '执行记录',
                      ),
                    ),
                    const PopupMenuDivider(height: 8),
                    PopupMenuItem(
                      value: 'toggle',
                      height: 44,
                      child: _ruleMenuItem(
                        icon: enabled
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                        label: enabled ? '停用规则' : '启用规则',
                        color: enabled
                            ? const Color(0xFFBE123C)
                            : const Color(0xFF15803D),
                      ),
                    ),
                  ],
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: DunesColors.text3,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfig() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      children: [
        _configCard(
          title: '日报提醒',
          child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('开启日报提醒'),
                value: _reportReminderEnabled,
                onChanged: (value) =>
                    setState(() => _reportReminderEnabled = value),
              ),
              Row(
                children: [
                  Expanded(child: _timeField(_firstReminderController, '首次提醒')),
                  const SizedBox(width: 10),
                  Expanded(child: _timeField(_deadlineController, '日报截止')),
                ],
              ),
            ],
          ),
        ),
        _configCard(
          title: '任务规则',
          child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('允许使用周期任务'),
                value: _recurringTaskEnabled,
                onChanged: (value) =>
                    setState(() => _recurringTaskEnabled = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用任务变更审批'),
                subtitle: const Text('修改标题、内容、截止日或负责人时，由发起人直属上级一级审批；无直属上级则当场生效'),
                value: _taskApprovalEnabled,
                onChanged: (value) =>
                    setState(() => _taskApprovalEnabled = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('指派需要接收确认'),
                subtitle: const Text('仅新建子目标指派他人时生效；运行中转派走直属上级审批'),
                value: _assignmentConfirmationEnabled,
                onChanged: (value) =>
                    setState(() => _assignmentConfirmationEnabled = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        FilledButton.icon(
          onPressed: _saving ? null : _saveConfig,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('保存任务配置'),
        ),
      ],
    );
  }

  Widget _timeField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'HH:mm',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _configCard({required String title, required Widget child}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    final holidays = _calendarDays.where((day) => day.isHoliday).length;
    final adjusted = _calendarDays.where((day) => day.isAdjustedWorkday).length;
    final weekends = _calendarDays
        .where((day) => day.dayType == 'weekend')
        .length;
    final visible = _calendarDays
        .where((day) {
          switch (_calendarFilter) {
            case 'holiday':
              return day.isHoliday;
            case 'adjusted':
              return day.isAdjustedWorkday;
            case 'nonWorkday':
              return !day.isWorkday;
            case 'exception':
              return day.isHoliday || day.isAdjustedWorkday;
            default:
              return true;
          }
        })
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      children: [
        const Text(
          '任务日报仅使用这里的任务日历判断法定节假日和调休上班日，不修改考勤、请假或人事数据。',
          style: TextStyle(fontSize: 13, color: DunesColors.text3, height: 1.4),
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _calendarYearController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '年份',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => unawaited(_loadCalendar()),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : () => unawaited(_loadCalendar()),
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('查询'),
                ),
                FilledButton.icon(
                  onPressed: _syncingCalendar ? null : _syncCalendar,
                  icon: _syncingCalendar
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: Text(_syncingCalendar ? '同步中…' : '同步节假日'),
                ),
              ],
            ),
          ),
        ),
        if (_calendarDays.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _calendarStat('全年日期', '${_calendarDays.length}', kTaskPurple),
              _calendarStat('法定节假日', '$holidays', const Color(0xFFE35D4C)),
              _calendarStat('调休上班', '$adjusted', const Color(0xFF2F8F7E)),
              _calendarStat('普通周末', '$weekends', const Color(0xFF6B7280)),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _calendarFilterChip('exception', '节假日及调休'),
              _calendarFilterChip('holiday', '法定节假日'),
              _calendarFilterChip('adjusted', '调休上班'),
              _calendarFilterChip('nonWorkday', '所有非工作日'),
              _calendarFilterChip('all', '全年日历'),
            ],
          ),
          const SizedBox(height: 10),
          if (visible.isEmpty)
            _emptyState(Icons.event_busy_outlined, '暂无对应日期', '可以切换筛选条件查看全年日历。')
          else
            for (final day in visible) _calendarDayCard(day),
        ] else
          _emptyState(
            Icons.event_available_outlined,
            '尚未同步该年度日历',
            '点击“同步节假日”获取法定节假日和调休安排。',
          ),
      ],
    );
  }

  Widget _calendarStat(String label, String value, Color color) {
    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
        ],
      ),
    );
  }

  Widget _calendarFilterChip(String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _calendarFilter == value,
      onSelected: (_) => setState(() => _calendarFilter = value),
    );
  }

  Widget _calendarDayCard(TaskCalendarDay day) {
    final date = DateTime.tryParse(day.date);
    final weekday = date == null
        ? ''
        : '星期${const ['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1]}';
    final color = day.isHoliday
        ? const Color(0xFFE35D4C)
        : day.isAdjustedWorkday
        ? const Color(0xFF2F8F7E)
        : const Color(0xFF6B7280);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          day.isAdjustedWorkday
              ? Icons.work_history_outlined
              : Icons.event_outlined,
          color: color,
        ),
        title: Text('${day.date}  $weekday'),
        subtitle: Text(day.typeLabel),
        trailing: _statusPill(day.isWorkday ? '工作日' : '休息日', day.isWorkday),
      ),
    );
  }

  Widget _buildImport() {
    final preview = _preview;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      children: [
        const Text(
          '选择任务或试用期任务模板，先校验再提交，不会直接修改现有任务。',
          style: TextStyle(fontSize: 13, color: DunesColors.text3, height: 1.4),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('任务'),
              selected: _importKind == 'task',
              onSelected: (_) => setState(() {
                _importKind = 'task';
                _preview = null;
              }),
            ),
            ChoiceChip(
              label: const Text('试用期任务'),
              selected: _importKind == 'probation',
              onSelected: (_) => setState(() {
                _importKind = 'probation';
                _preview = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.table_chart_outlined, color: kTaskPurple),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _selectedFileName ?? '尚未选择 Excel 文件',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                OutlinedButton(
                  onPressed: _pickImportFile,
                  child: const Text('选择文件'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _previewing ? null : _previewImport,
          icon: _previewing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.fact_check_outlined),
          label: const Text('预览并校验'),
        ),
        if (preview != null) ...[
          const SizedBox(height: 14),
          _configCard(
            title: '校验结果',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '共 ${preview.total} 行 · ${preview.valid} 行可导入 · ${preview.invalid} 行有错误',
                ),
                if (preview.errors.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final error in preview.errors.take(8))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• $error',
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                ],
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _committing || preview.invalid > 0
                      ? null
                      : _commitImport,
                  child: Text(_committing ? '提交中…' : '确认导入'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) {
      return _emptyState(Icons.history_rounded, '暂无导入记录', '确认导入后会在这里保留记录。');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final item = _history[index];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: const Icon(Icons.description_outlined, color: kTaskPurple),
            title: Text(item.fileName.isEmpty ? '未命名文件' : item.fileName),
            subtitle: Text(
              [
                if (item.importKind.isNotEmpty) item.importKind,
                if (item.createdAt.isNotEmpty) item.createdAt,
                if (item.total > 0) '${item.total} 行',
              ].join(' · '),
            ),
            trailing: _statusPill(
              item.status.isEmpty ? '未知' : item.status,
              item.status == 'success',
            ),
          ),
        );
      },
    );
  }

  Widget _statusPill(String text, bool positive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: positive ? const Color(0xFFE8F7F0) : const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: positive ? const Color(0xFF15803D) : const Color(0xFFBE123C),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildError(String message, {required VoidCallback onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 38,
              color: DunesColors.text3,
            ),
            const SizedBox(height: 10),
            const Text(
              '任务管理服务暂不可用',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: kTaskPurple),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
          ],
        ),
      ),
    );
  }
}
