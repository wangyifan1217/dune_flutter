import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'qianji_cash_flow_api.dart';

const _themePurple = Color(0xFF7B5CD8);
const _cardBorder = Color(0xFFE8EAED);

const _presetQuestions = <String>[
  '综合分析当前区间资金情况',
  '哪些账户需要关注？',
  '流入流出结构怎么样？',
  '经营现金流健康吗？',
];

class CashFlowAiMessage {
  const CashFlowAiMessage({
    required this.role,
    required this.text,
    this.error = false,
  });

  final String role;
  final String text;
  final bool error;
}

/// 会话挂在看板页生命周期之外：关掉弹层仍继续轮询，再打开能看到记录。
class CashFlowAiController extends ChangeNotifier {
  CashFlowAiController._(this._session);

  static CashFlowAiController? _instance;

  static CashFlowAiController bind(AuthSession session) {
    final cur = _instance;
    if (cur != null && cur._session.userId == session.userId) {
      cur._session = session;
      return cur;
    }
    cur?._shutdown();
    final next = CashFlowAiController._(session);
    _instance = next;
    return next;
  }

  AuthSession _session;
  final List<CashFlowAiMessage> messages = [];
  bool busy = false;
  int _seq = 0;
  bool _shutdownFlag = false;

  bool get hasSession => messages.isNotEmpty || busy;

  Future<void> ask({
    required String question,
    required DateTime from,
    required DateTime to,
    String? company,
  }) async {
    final text = question.trim();
    if (text.isEmpty || busy || _shutdownFlag) return;
    messages.add(CashFlowAiMessage(role: 'user', text: text));
    busy = true;
    notifyListeners();
    final seq = ++_seq;
    try {
      final api = QianjiCashFlowApi(_session);
      final history = messages
          .where((m) => !m.error && m.text.trim().isNotEmpty)
          .map((m) => QianjiCashFlowChatMessage(role: m.role, content: m.text))
          .toList();
      final started = await api.startAnalyze(
        from: from,
        to: to,
        company: company,
        messages: history,
      );
      if (_shutdownFlag || seq != _seq) return;
      final job = await _poll(api, started.id, seq);
      if (_shutdownFlag || seq != _seq) return;
      if (job == null) {
        messages.add(
          const CashFlowAiMessage(
            role: 'assistant',
            text: 'AI 分析超时，请稍后重试',
            error: true,
          ),
        );
      } else if (job.isFailed || job.answer.isEmpty) {
        messages.add(
          CashFlowAiMessage(
            role: 'assistant',
            text: job.error.isEmpty ? 'AI 未返回内容，请换个问题再试。' : job.error,
            error: true,
          ),
        );
      } else {
        messages.add(CashFlowAiMessage(role: 'assistant', text: job.answer));
      }
    } catch (e) {
      if (_shutdownFlag || seq != _seq) return;
      messages.add(
        CashFlowAiMessage(
          role: 'assistant',
          text: e.toString().replaceFirst('Exception: ', ''),
          error: true,
        ),
      );
    } finally {
      if (!_shutdownFlag && seq == _seq) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<QianjiCashFlowAnalyzeJob?> _poll(
    QianjiCashFlowApi api,
    String id,
    int seq,
  ) async {
    final deadline = DateTime.now().add(const Duration(minutes: 3, seconds: 30));
    while (!_shutdownFlag && seq == _seq && DateTime.now().isBefore(deadline)) {
      final job = await api.getAnalyze(id);
      if (job.isDone || job.isFailed) return job;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    return null;
  }

  void clear() {
    _seq++;
    messages.clear();
    busy = false;
    notifyListeners();
  }

  void _shutdown() {
    _shutdownFlag = true;
    _seq++;
    dispose();
  }
}

class CashFlowAiSheet extends StatefulWidget {
  const CashFlowAiSheet({
    super.key,
    required this.controller,
    required this.from,
    required this.to,
    this.company,
    required this.rangeLabel,
    this.companyLabel,
  });

  final CashFlowAiController controller;
  final DateTime from;
  final DateTime to;
  final String? company;
  final String rangeLabel;
  final String? companyLabel;

  @override
  State<CashFlowAiSheet> createState() => _CashFlowAiSheetState();
}

class _CashFlowAiSheetState extends State<CashFlowAiSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSession);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  @override
  void didUpdateWidget(covariant CashFlowAiSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onSession);
      widget.controller.addListener(_onSession);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSession);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    setState(() {});
    _jumpToEnd();
  }

  void _ask(String question) {
    widget.controller.ask(
      question: question,
      from: widget.from,
      to: widget.to,
      company: widget.company,
    );
    _input.clear();
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height * 0.92;
    final busy = widget.controller.busy;
    final messages = widget.controller.messages;
    final subtitle = [
      '统计区间 ${widget.rangeLabel}',
      if ((widget.companyLabel ?? '').trim().isNotEmpty) widget.companyLabel!.trim(),
    ].join(' · ');
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _cardBorder,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 18, color: _themePurple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI分析',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: DunesColors.text,
                          ),
                        ),
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
                  if (widget.controller.hasSession)
                    IconButton(
                      tooltip: '清空会话',
                      onPressed: widget.controller.clear,
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: DunesColors.text3,
                      ),
                    ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20, color: DunesColors.text3),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _cardBorder),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                children: [
                  if (messages.isEmpty && !busy) const _IdleHint(),
                  for (final message in messages) _MessageBubble(message: message),
                  if (busy) const _LoadingBubble(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final q in _presetQuestions)
                    _PromptChip(
                      label: q,
                      enabled: !busy,
                      onTap: () => _ask(q),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: _cardBorder),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        enabled: !busy,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _ask(_input.text),
                        decoration: InputDecoration(
                          hintText: busy ? '后台分析中，关闭后仍会继续' : '自己提问，例如现金够不够用',
                          hintStyle: const TextStyle(
                            fontSize: 13,
                            color: DunesColors.text3,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF5F6F8),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _cardBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _cardBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _themePurple),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: busy ? null : () => _ask(_input.text),
                      style: IconButton.styleFrom(
                        backgroundColor: _themePurple,
                        disabledBackgroundColor: _themePurple.withValues(
                          alpha: 0.35,
                        ),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.send_rounded, size: 18),
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

class _IdleHint extends StatelessWidget {
  const _IdleHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 8, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '先选一个问题，或自己输入',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          SizedBox(height: 6),
          Text(
            '关掉窗口后分析仍会在后台继续，再打开能看到记录。右上角可清空会话。',
            style: TextStyle(fontSize: 13, height: 1.45, color: DunesColors.text3),
          ),
        ],
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? _themePurple.withValues(alpha: 0.08)
          : const Color(0xFFF5F6F8),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: enabled
                  ? _themePurple.withValues(alpha: 0.28)
                  : _cardBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: enabled ? _themePurple : DunesColors.text3,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingBubble extends StatelessWidget {
  const _LoadingBubble();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: _themePurple,
            ),
          ),
          SizedBox(width: 8),
          Text(
            '已提交，DeepSeek 后台分析中…',
            style: TextStyle(fontSize: 13, color: DunesColors.text3),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final CashFlowAiMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.86,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isUser
                  ? _themePurple.withValues(alpha: 0.10)
                  : message.error
                  ? DunesColors.coralSoft
                  : const Color(0xFFF7F6FB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: message.error
                    ? DunesColors.coral.withValues(alpha: 0.35)
                    : _cardBorder,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
              child: isUser || message.error
                  ? Padding(
                      padding: const EdgeInsets.only(right: 4, bottom: 4),
                      child: Text(
                        message.text,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: message.error
                              ? DunesColors.coral
                              : DunesColors.text,
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MarkdownBody(
                          data: message.text,
                          selectable: true,
                          softLineBreak: true,
                          styleSheet: _cashFlowMdStyle(),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: message.text),
                              );
                              if (!context.mounted) return;
                              showDunesToast(context, '已复制');
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: _themePurple,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.copy_outlined, size: 14),
                            label: const Text(
                              '复制',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

MarkdownStyleSheet _cashFlowMdStyle() {
  return MarkdownStyleSheet(
    p: DunesTypography.sans(
      fontSize: 13,
      height: 1.55,
      color: DunesColors.text,
    ),
    h1: DunesTypography.sans(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: DunesColors.text,
      height: 1.35,
    ),
    h2: DunesTypography.sans(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: DunesColors.text,
      height: 1.35,
    ),
    h3: DunesTypography.sans(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: DunesColors.text,
      height: 1.35,
    ),
    strong: DunesTypography.sans(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: DunesColors.text,
    ),
    listBullet: DunesTypography.sans(
      fontSize: 13,
      height: 1.55,
      color: DunesColors.text3,
    ),
    code: DunesTypography.sans(
      fontSize: 12,
      color: DunesColors.text,
    ).copyWith(backgroundColor: const Color(0xFFF0F1F4)),
  );
}
