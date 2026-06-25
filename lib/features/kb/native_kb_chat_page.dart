import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'native_kb_models.dart';
import 'native_kb_service.dart';

class NativeKbChatPage extends StatefulWidget {
  const NativeKbChatPage({
    super.key,
    required this.session,
    required this.navigation,
    required this.chatKind,
    required this.docId,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final String chatKind;
  final String? docId;

  @override
  State<NativeKbChatPage> createState() => _NativeKbChatPageState();
}

class _NativeKbChatPageState extends State<NativeKbChatPage> {
  late final NativeKbService _service;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<NativeKbMessage> _messages = <NativeKbMessage>[];
  late String _sessionId;
  String _subtitle = '基于企业知识库回答';
  String _docTitle = '问知识库 AI';
  bool _loading = true;
  bool _sending = false;
  String? _error;

  bool get _isDocChat => widget.chatKind.toUpperCase() == 'KB_DOC' && (widget.docId?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _service = NativeKbService(session: widget.session);
    _sessionId = _service.newChatSessionId();
    _bootstrap();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isDocChat) {
        final doc = await _service.fetchDocumentDetail(widget.docId!);
        if (!mounted) return;
        setState(() {
          _docTitle = doc.title;
          _subtitle = '基于单篇文档回答';
        });
      } else {
        final summary = await _service.fetchSummary();
        if (!mounted) return;
        setState(() {
          _docTitle = '问知识库 AI';
          _subtitle = summary.documentCount > 0
              ? '已索引 ${summary.documentCount} 篇 · ${summary.categoryCount} 个文件夹'
              : '请先上传知识库文档';
        });
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final userId = DateTime.now().millisecondsSinceEpoch;
    final assistantId = userId + 1;
    setState(() {
      _sending = true;
      _messages.add(NativeKbMessage(id: userId, role: 'user', text: text, createdAt: DateTime.now()));
      _messages.add(NativeKbMessage(
        id: assistantId,
        role: 'assistant',
        text: '正在检索知识库…',
        streaming: true,
        createdAt: DateTime.now(),
      ));
    });
    _input.clear();
    _scrollBottom();

    try {
      var citations = <NativeKbCitation>[];
      await _service.sendKbMessage(
        text: text,
        sessionId: _sessionId,
        onDelta: (acc) {
          if (!mounted) return;
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == assistantId);
            if (idx >= 0) {
              _messages[idx] = _messages[idx].copyWith(text: acc, streaming: true);
            }
          });
          _scrollBottom();
        },
        onCitations: (c) => citations = c,
      );
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == assistantId);
        if (idx >= 0) {
          _messages[idx] = _messages[idx].copyWith(
            citations: citations,
            streaming: false,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == assistantId);
        if (idx >= 0) {
          _messages[idx] = _messages[idx].copyWith(
            text: e.toString(),
            streaming: false,
          );
        }
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _newChat() {
    setState(() {
      _messages.clear();
      _sessionId = _service.newChatSessionId();
    });
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_error != null)
              Expanded(child: _buildError())
            else ...[
              if (_messages.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: DunesColors.accentSoft,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, size: 12, color: DunesColors.accentDeep),
                        SizedBox(width: 6),
                        Text('知识库助手 · 可引用原文回答', style: TextStyle(fontSize: 10, color: DunesColors.accentDeep)),
                      ],
                    ),
                  ),
                ),
              Expanded(child: _buildMessages()),
              _buildInput(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => widget.navigation.go('K1'),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text('知识库', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    SizedBox(width: 6),
                    _AiBadge(),
                  ],
                ),
                Text(_subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: DunesColors.text3)),
                if (_isDocChat)
                  Text(_docTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: DunesColors.accentDeep)),
              ],
            ),
          ),
          IconButton(onPressed: _newChat, icon: const Icon(Icons.add, size: 20), tooltip: '新对话'),
          IconButton(
            onPressed: () => widget.navigation.go('K1'),
            icon: const Icon(Icons.menu_book_outlined, size: 20),
            tooltip: '我的知识库',
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _bootstrap, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      itemCount: _messages.length,
      itemBuilder: (_, index) {
        final m = _messages[index];
        final mine = m.role == 'user';
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: mine ? DunesColors.accent : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: mine ? null : Border.all(color: DunesColors.borderSoft),
                  ),
                  child: Text(
                    m.text,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: mine ? Colors.white : DunesColors.text,
                    ),
                  ),
                ),
                if (!mine && m.citations.isNotEmpty)
                  ...m.citations.take(3).map(_citationCard),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _citationCard(NativeKbCitation c) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F6F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.sourceTitle, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: DunesColors.accentDeep)),
          if (c.page != null)
            Text('第 ${c.page} 页', style: const TextStyle(fontSize: 9, color: DunesColors.text3)),
          const SizedBox(height: 4),
          Text(
            c.chunkText,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, height: 1.4, color: DunesColors.text2),
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              enabled: !_sending,
              decoration: InputDecoration(
                hintText: _sending ? '知识库助手思考中…' : '向知识库提问…',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _sending ? null : _send,
            style: FilledButton.styleFrom(backgroundColor: DunesColors.accentDeep),
            child: Text(_sending ? '…' : '发送'),
          ),
        ],
      ),
    );
  }
}

class _AiBadge extends StatelessWidget {
  const _AiBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: DunesColors.accentSoft,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text('AI', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: DunesColors.accentDeep)),
    );
  }
}
