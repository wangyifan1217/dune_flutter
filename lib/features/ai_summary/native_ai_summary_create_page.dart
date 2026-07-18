import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'ai_summary_models.dart';
import 'ai_summary_participants.dart';
import 'ai_summary_service.dart';

/// 发起智能总结：主题 / 模板 / 多选会话 / 日期。
class NativeAiSummaryCreatePage extends StatefulWidget {
  const NativeAiSummaryCreatePage({
    super.key,
    required this.session,
    required this.onBack,
    required this.onCreated,
    this.initialConversationIds = const <int>[],
  });

  final AuthSession session;
  final VoidCallback onBack;
  final ValueChanged<AiSummaryItem> onCreated;
  /// 从 IM 会话进入时预绑的会话 ID。
  final List<int> initialConversationIds;

  @override
  State<NativeAiSummaryCreatePage> createState() =>
      _NativeAiSummaryCreatePageState();
}

class _NativeAiSummaryCreatePageState extends State<NativeAiSummaryCreatePage> {
  late final AiSummaryService _service;
  late final ConversationService _conversations;
  final TextEditingController _themeController = TextEditingController();

  List<AiSummaryTemplate> _templates = const <AiSummaryTemplate>[];
  final Set<int> _selectedIds = <int>{};
  List<NativeConversation> _selectedConversations = const <NativeConversation>[];
  late DateTime _rangeStart;
  late DateTime _rangeEnd;
  String _templateId = 'custom';
  bool _loadingMeta = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _rangeStart = DateTime(today.year, today.month, today.day);
    _rangeEnd = _rangeStart;
    _service = AiSummaryService(session: widget.session);
    _conversations = ConversationService(session: widget.session);
    _selectedIds.addAll(
      widget.initialConversationIds.where((id) => id > 0),
    );
    _loadMeta();
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    try {
      final templates = await _service.fetchTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates.isEmpty
            ? const [
                AiSummaryTemplate(
                  id: 'project_progress',
                  title: '汇总项目进展',
                  subtitle: '与团队成员一起总结进展',
                ),
                AiSummaryTemplate(
                  id: 'task_progress',
                  title: '跟踪任务进度',
                  subtitle: '汇总任务完成情况',
                ),
                AiSummaryTemplate(
                  id: 'weekly_report',
                  title: '总结团队周报',
                  subtitle: '总结团队成员每周的工作',
                ),
                AiSummaryTemplate(
                  id: 'custom',
                  title: '自定义主题',
                  subtitle: '输入你想总结的主题',
                ),
              ]
            : templates;
        _loadingMeta = false;
        if (_templates.any((t) => t.id == 'custom')) {
          _templateId = 'custom';
        } else if (_templates.isNotEmpty) {
          _templateId = _templates.first.id;
        }
      });
      await _hydrateSelected();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMeta = false);
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '加载失败'),
        kind: DunesToastKind.error,
      );
    }
  }

  Future<void> _hydrateSelected() async {
    if (_selectedIds.isEmpty) {
      if (mounted) {
        setState(() => _selectedConversations = const <NativeConversation>[]);
      }
      return;
    }
    final list = await resolveAiSummaryConversations(
      service: _conversations,
      conversationIds: _selectedIds.toList(growable: false),
    );
    if (!mounted) return;
    setState(() => _selectedConversations = list);
  }

  ThemeData _purplePickerTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: DunesColors.brandPurple,
        onPrimary: Colors.white,
        secondary: DunesColors.brandPurpleDeep,
        surface: Colors.white,
      ),
      datePickerTheme: DatePickerThemeData(
        headerBackgroundColor: DunesColors.brandPurple,
        headerForegroundColor: Colors.white,
        todayForegroundColor: WidgetStateProperty.all(DunesColors.brandPurple),
        todayBackgroundColor: WidgetStateProperty.all(
          DunesColors.brandPurpleSoft,
        ),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return null;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return DunesColors.brandPurple;
          }
          return null;
        }),
        rangeSelectionBackgroundColor: DunesColors.brandPurpleSoft,
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: DunesColors.brandPurple,
        ),
        cancelButtonStyle: TextButton.styleFrom(
          foregroundColor: DunesColors.brandPurple,
        ),
      ),
    );
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _rangeStart, end: _rangeEnd),
      helpText: '选择总结周期',
      saveText: '确定',
      cancelText: '取消',
      builder: (context, child) {
        return Theme(data: _purplePickerTheme(context), child: child!);
      },
    );
    if (picked == null || !mounted) return;
    final span = picked.end.difference(picked.start).inDays + 1;
    if (span > 31) {
      showDunesToast(context, '时间跨度不能超过 31 天', kind: DunesToastKind.error);
      return;
    }
    setState(() {
      _rangeStart = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _rangeEnd = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
  }

  Future<void> _pickConversations() async {
    final result = await showConversationMultiPickerSheet(
      context: context,
      service: _conversations,
      title: '选择聊天（可多选）',
      multiSelect: true,
      initialSelected: _selectedIds,
      maxCount: 20,
    );
    if (result == null || !mounted) return;
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(result);
    });
    await _hydrateSelected();
  }

  Future<void> _openParticipantsSheet() async {
    await showAiSummaryParticipantsSheet(
      context: context,
      service: _conversations,
      conversations: _selectedConversations,
      title: '参与会话',
      editable: true,
      onAdd: _pickConversations,
      onConversationsChanged: (next) {
        setState(() {
          _selectedConversations = next;
          _selectedIds
            ..clear()
            ..addAll(next.map((c) => c.id));
        });
      },
    );
  }

  bool get _canSubmit => !_submitting && _selectedIds.isNotEmpty;

  void _applyTemplate(AiSummaryTemplate t) {
    setState(() {
      _templateId = t.id;
      if (t.id != 'custom' && _themeController.text.trim().isEmpty) {
        _themeController.text = t.title;
      }
    });
  }

  Future<void> _submit() async {
    final theme = _themeController.text.trim();
    if (theme.isEmpty) {
      showDunesToast(context, '请填写总结主题', kind: DunesToastKind.error);
      return;
    }
    if (_selectedIds.isEmpty) {
      showDunesToast(context, '请选择至少一个聊天会话', kind: DunesToastKind.error);
      return;
    }
    final confirmed = await confirmAiSummaryAction(
      context: context,
      title: '开始总结',
      message:
          '将对 ${_selectedIds.length} 个会话（$_rangeLabel）生成智能总结，确认开始？',
      confirmLabel: '开始总结',
    );
    if (!confirmed || !mounted) return;

    setState(() => _submitting = true);
    try {
      final range = AiSummaryService.inclusiveDayRange(_rangeStart, _rangeEnd);
      final item = await _service.create(
        theme: theme,
        template: _templateId,
        conversationIds: _selectedIds.toList(growable: false),
        from: range.$1,
        to: range.$2,
      );
      if (!mounted) return;
      widget.onCreated(item);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '创建失败'),
        kind: DunesToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _fmtDay(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (d == today) return '今天';
    return '${d.month}/${d.day}';
  }

  String get _rangeLabel {
    if (_rangeStart == _rangeEnd) return _fmtDay(_rangeStart);
    return '${_fmtDay(_rangeStart)} – ${_fmtDay(_rangeEnd)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.close_rounded, size: 24),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _pickRange,
                    style: TextButton.styleFrom(
                      foregroundColor: DunesColors.brandPurple,
                    ),
                    icon: const Icon(Icons.date_range_outlined, size: 16),
                    label: Text(_rangeLabel),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loadingMeta
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        TextField(
                          controller: _themeController,
                          style: DunesTypography.sans(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: '输入聊天内你想总结的主题',
                            hintStyle: DunesTypography.sans(
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFFC4C4C4),
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                        const SizedBox(height: 8),
                        AiSummaryParticipantsRow(
                          conversations: _selectedConversations,
                          service: _conversations,
                          onTap: _selectedConversations.isEmpty
                              ? _pickConversations
                              : _openParticipantsSheet,
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _pickConversations,
                            icon: const Icon(
                              Icons.person_add_alt_1_outlined,
                              size: 18,
                            ),
                            label: const Text('添加会话'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: DunesColors.brandPurpleDeep,
                              side: const BorderSide(
                                color: DunesColors.brandPurpleLine,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '试试总结',
                          style: DunesTypography.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ..._templates
                            .where((t) => t.id != 'custom')
                            .map(
                              (t) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _TemplateTile(
                                  template: t,
                                  selected: _templateId == t.id,
                                  onTap: () => _applyTemplate(t),
                                ),
                              ),
                            ),
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFFF0F0F0)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickConversations,
                        icon: const Icon(
                          Icons.person_add_alt_1_outlined,
                          size: 18,
                        ),
                        label: const Text('添加会话'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _canSubmit ? _submit : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: DunesColors.brandPurple,
                          disabledBackgroundColor: const Color(0xFFE5E7EB),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          _submitting
                              ? '提交中…'
                              : (_selectedIds.isEmpty ? '请先选择会话' : '开始总结'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final AiSummaryTemplate template;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon {
    switch (template.id) {
      case 'project_progress':
        return Icons.description_outlined;
      case 'task_progress':
        return Icons.checklist_rounded;
      case 'weekly_report':
        return Icons.calendar_month_outlined;
      default:
        return Icons.auto_awesome_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DunesColors.brandPurpleSoft : const Color(0xFFF7F8FA),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(_icon, size: 22, color: const Color(0xFF4B5563)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.title,
                      style: DunesTypography.sans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      template.subtitle,
                      style: DunesTypography.sans(
                        fontSize: 12.5,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle,
                  size: 18,
                  color: DunesColors.brandPurple,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
