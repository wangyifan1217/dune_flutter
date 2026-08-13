import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../meeting/meeting_minutes_markdown.dart';
import '../shell/dunes_toast.dart';
import 'task_models.dart';

const _themePurple = Color(0xFF7B5CD8);

/// 一条 AI 分析记录（提问 + 异步生成的回答）。
class TaskAnalysisItem {
  const TaskAnalysisItem({
    required this.id,
    required this.question,
    required this.status,
    required this.answer,
    required this.detail,
    required this.createdAt,
  });

  final int id;
  final String question;
  final String status; // running | done | failed
  final String answer;
  final String detail;
  final DateTime? createdAt;

  bool get isRunning => status == 'running';
  bool get isDone => status == 'done';

  /// 服务重启等异常导致的僵尸 running：超过 5 分钟按失败处理。
  bool get isStale {
    if (!isRunning || createdAt == null) return false;
    return DateTime.now().difference(createdAt!) > const Duration(minutes: 5);
  }

  factory TaskAnalysisItem.fromJson(Map<String, dynamic> json) {
    return TaskAnalysisItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      question: '${json['question'] ?? ''}',
      status: '${json['status'] ?? ''}',
      answer: '${json['answer'] ?? ''}',
      detail: '${json['detail'] ?? ''}',
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
    );
  }
}

/// 任务 AI 分析接口（全部为新增端点）。
class TaskAnalysisApi {
  TaskAnalysisApi(this.session);

  final AuthSession session;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${session.token}',
    'Content-Type': 'application/json',
  };

  Uri _uri(int taskId) {
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/qianji/tasks/$taskId/analysis');
  }

  dynamic _unwrap(http.Response resp) {
    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    if (body is! Map) throw Exception('invalid response');
    if (body['success'] == false || resp.statusCode >= 400) {
      throw Exception('${body['message'] ?? 'HTTP ${resp.statusCode}'}');
    }
    return body['data'];
  }

  Future<List<TaskAnalysisItem>> list(int taskId) async {
    final resp = await http.get(_uri(taskId), headers: _headers);
    final data = _unwrap(resp);
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    return (map['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => TaskAnalysisItem.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<TaskAnalysisItem> create(int taskId, String question) async {
    final resp = await http.post(
      _uri(taskId),
      headers: _headers,
      body: jsonEncode({'question': question.trim()}),
    );
    final data = _unwrap(resp);
    return TaskAnalysisItem.fromJson(Map<String, dynamic>.from(data as Map));
  }
}

/// 打开任务 AI 分析：手机底部滑出，PC 端对话框（与会议详情一致）。
Future<void> showTaskAiAnalysis({
  required BuildContext context,
  required AuthSession session,
  required TaskItem task,
}) {
  if (isDesktopCommOnly) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 28,
          ),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: size.height * 0.85,
              minWidth: 440,
              minHeight: 380,
            ),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: SelectionArea(
                child: _TaskAiAnalysisPanel(
                  session: session,
                  task: task,
                  onClose: () => Navigator.of(ctx).maybePop(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      return Padding(
        // 键盘弹出时上推，避免输入框被遮挡
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Container(
          height: size.height * 0.82,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          clipBehavior: Clip.antiAlias,
          child: _TaskAiAnalysisPanel(
            session: session,
            task: task,
            onClose: () => Navigator.of(ctx).maybePop(),
          ),
        ),
      );
    },
  );
}

class _TaskAiAnalysisPanel extends StatefulWidget {
  const _TaskAiAnalysisPanel({
    required this.session,
    required this.task,
    required this.onClose,
  });

  final AuthSession session;
  final TaskItem task;
  final VoidCallback onClose;

  @override
  State<_TaskAiAnalysisPanel> createState() => _TaskAiAnalysisPanelState();
}

class _TaskAiAnalysisPanelState extends State<_TaskAiAnalysisPanel> {
  late final TaskAnalysisApi _api = TaskAnalysisApi(widget.session);
  final _questionCtrl = TextEditingController();
  List<TaskAnalysisItem> _items = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _questionCtrl.dispose();
    super.dispose();
  }

  bool get _hasFreshRunning => _items.any((e) => e.isRunning && !e.isStale);

  Future<void> _reload() async {
    try {
      final items = await _api.list(widget.task.id);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
      _schedulePoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    if (!_hasFreshRunning) return;
    _pollTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) _reload();
    });
  }

  Future<void> _send() async {
    if (_sending || _hasFreshRunning) return;
    final q = _questionCtrl.text.trim();
    setState(() => _sending = true);
    try {
      final row = await _api.create(widget.task.id, q);
      if (!mounted) return;
      _questionCtrl.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _items = [row, ..._items]);
      _schedulePoll();
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18, color: _themePurple),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AI 分析',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        widget.task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: widget.onClose,
                  icon: const Icon(
                    Icons.close,
                    size: 20,
                    color: DunesColors.text2,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEDEFF2)),
          Expanded(child: _buildBody()),
          const Divider(height: 1, color: Color(0xFFEDEFF2)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _questionCtrl,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: '输入问题，留空则做综合分析',
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: DunesColors.text3,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF5F6F8),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _themePurple,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _sending || _hasFreshRunning ? null : _send,
                  child: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_hasFreshRunning ? '分析中…' : '分析'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: _themePurple,
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: DunesColors.text3),
              ),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: _reload, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'AI 会结合任务信息、进展记录，并从关联的知识库文档中检索相关内容回答。\n输入问题，或直接点「分析」做综合分析。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: DunesColors.text3,
              height: 1.6,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _items.length,
      itemBuilder: (context, i) => _analysisCard(_items[i]),
    );
  }

  Widget _analysisCard(TaskAnalysisItem item) {
    final question = item.question.trim().isEmpty
        ? '综合分析'
        : item.question.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '问：$question',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text2,
                  ),
                ),
              ),
              if (item.createdAt != null)
                Text(
                  _fmtTime(item.createdAt!),
                  style: const TextStyle(
                    fontSize: 11,
                    color: DunesColors.text3,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (item.isRunning && !item.isStale)
            const Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _themePurple,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'AI 分析中，请稍候…',
                  style: TextStyle(fontSize: 13, color: DunesColors.text3),
                ),
              ],
            )
          else if (item.isDone)
            MeetingMinutesMarkdown(markdown: item.answer)
          else
            Text(
              item.isStale
                  ? '分析超时，请重新发起'
                  : (item.detail.trim().isEmpty
                        ? '分析失败，请稍后重试'
                        : item.detail.trim()),
              style: const TextStyle(fontSize: 13, color: Color(0xFFB4552D)),
            ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime t) {
    final local = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.month}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}
