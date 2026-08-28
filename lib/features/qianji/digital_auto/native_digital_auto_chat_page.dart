import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/layout/chat_layout.dart';
import '../../../core/theme/dunes_theme.dart';
import '../../auth/auth_session.dart';
import 'digital_auto_agent.dart';
import 'digital_auto_config.dart';
import 'digital_auto_history_store.dart';

const _assistantPurple = Color(0xFF7B5CD8);

class _ChatLine {
  _ChatLine({required this.role, this.text = ''});

  final String role;
  String text;
  String toolStatus = '';
}

class NativeDigitalAutoChatPage extends StatefulWidget {
  const NativeDigitalAutoChatPage({
    super.key,
    required this.session,
    required this.onBack,
    this.configuration = DigitalAutoConfig.channelDock,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final DigitalAutoAssistantConfig configuration;

  @override
  State<NativeDigitalAutoChatPage> createState() =>
      _NativeDigitalAutoChatPageState();
}

class _NativeDigitalAutoChatPageState extends State<NativeDigitalAutoChatPage>
    with WidgetsBindingObserver {
  late final DigitalAutoAgent _agent;
  late final DigitalAutoHistoryStore _history;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final List<_ChatLine> _lines = [];
  bool _connecting = true;
  bool _sending = false;
  String _connectError = '';
  double _lastKeyboardInset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _agent = DigitalAutoAgent(
      session: widget.session,
      configuration: widget.configuration,
    );
    _history = DigitalAutoHistoryStore(
      session: widget.session,
      configuration: widget.configuration,
    );
    _connect(restoreHistory: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_persistHistory());
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    final inset = View.of(context).viewInsets.bottom;
    final keyboardOpening = _focus.hasFocus && inset > _lastKeyboardInset + 1;
    _lastKeyboardInset = inset;
    if (keyboardOpening) _jumpToEnd();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_persistHistory());
    }
  }

  Future<void> _persistHistory() async {
    await _history.save(
      lines: [
        for (final line in _lines) {'role': line.role, 'text': line.text},
      ],
      messages: _agent.exportMessages(),
    );
  }

  String _friendlyError(Object e) {
    final raw = e.toString().replaceFirst('Exception: ', '');
    if (raw.contains('404') ||
        raw.contains('502') ||
        raw.contains('503') ||
        raw.contains('Connection') ||
        raw.contains('SocketException')) {
      return '数字配置服务暂未接通，稍后再试。';
    }
    if (raw.contains('401') || raw.contains('登录')) {
      return '登录已失效，请重新登录后再试。';
    }
    return raw;
  }

  Future<void> _connect({bool restoreHistory = false}) async {
    setState(() {
      _connecting = true;
      _connectError = '';
    });
    try {
      await _agent.connect(resetMessages: false);
      if (restoreHistory) {
        final snap = await _history.load();
        if (snap != null && snap.lines.isNotEmpty) {
          _agent.hydrateMessages(snap.messages);
          _lines
            ..clear()
            ..addAll([
              for (final row in snap.lines)
                _ChatLine(
                  role: row['role'] ?? 'assistant',
                  text: row['text'] ?? '',
                ),
            ]);
        } else {
          _agent.startFresh();
        }
      } else if (_agent.exportMessages().isEmpty) {
        _agent.startFresh();
      }
      if (!mounted) return;
      setState(() => _connecting = false);
      _jumpToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectError = _friendlyError(e);
      });
    }
  }

  Future<void> _newConversation() async {
    _controller.clear();
    await _history.clear();
    setState(() {
      _lines.clear();
      _connectError = '';
      _connecting = true;
    });
    try {
      await _agent.connect(resetMessages: true);
      if (!mounted) return;
      setState(() => _connecting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectError = _friendlyError(e);
      });
    }
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _sending || _connecting) return;
    if (_connectError.isNotEmpty) {
      await _connect();
      if (_connectError.isNotEmpty) return;
    }
    setState(() {
      _sending = true;
      _lines.add(_ChatLine(role: 'user', text: text));
      _lines.add(_ChatLine(role: 'assistant'));
    });
    _controller.clear();
    _jumpToEnd();
    try {
      await _agent.send(
        text,
        onUpdate: (event) {
          if (!mounted) return;
          setState(() {
            final last = _lines.isEmpty ? null : _lines.last;
            if (last == null || last.role != 'assistant') return;
            if (event.reply.isNotEmpty) last.text = event.reply;
            last.toolStatus = event.toolStatus;
          });
          _jumpToEnd();
        },
        onConfirmToolCall: _confirmToolCall,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final last = _lines.isEmpty ? null : _lines.last;
        if (last != null && last.role == 'assistant') {
          last.text = last.text.isEmpty ? _friendlyError(e) : last.text;
          last.toolStatus = '';
        }
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        unawaited(_persistHistory());
      }
    }
  }

  Future<bool> _confirmToolCall(
    DigitalAutoToolConfirmation confirmation,
  ) async {
    if (!mounted) return false;
    final actionItem =
        (confirmation.arguments['actionItem'] ??
                confirmation.arguments['title'] ??
                confirmation.arguments['content'] ??
                '')
            .toString()
            .trim();
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认完成行动项'),
        content: Text(
          actionItem.isEmpty
              ? '模型请求将一项会议行动项标记为完成。确认后才会执行。'
              : '确认将以下行动项标记为完成？\n\n$actionItem',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认完成'),
          ),
        ],
      ),
    );
    return approved ?? false;
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF5F6F8),
      body: SafeArea(
        bottom: false,
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          tween: Tween(begin: 0.08, end: 0),
          builder: (context, offset, child) => Transform.translate(
            offset: Offset(MediaQuery.sizeOf(context).width * offset, 0),
            child: Opacity(opacity: 1 - offset * 4, child: child),
          ),
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: ListView(
                    controller: _scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                    children: [
                      _buildWelcomeCard(),
                      if (_connecting) ...[
                        const SizedBox(height: 14),
                        _StatusBanner(
                          icon: Icons.sync_rounded,
                          text: '正在连接数字配置服务…',
                        ),
                      ],
                      if (_connectError.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _StatusBanner(
                          icon: Icons.info_outline_rounded,
                          text: _connectError,
                          actionLabel: '重试',
                          onAction: _connecting ? null : _connect,
                        ),
                      ],
                      for (final line in _lines) ...[
                        const SizedBox(height: 14),
                        if (line.role == 'user')
                          _UserBubble(text: line.text)
                        else
                          _AssistantBubble(
                            text: line.text,
                            toolStatus: line.toolStatus,
                            busy: _sending && identical(line, _lines.last),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              _buildComposer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final wide = isWideChatLayout(context);
    return Container(
      padding: EdgeInsets.fromLTRB(4, 8, wide ? 8 : 4, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8EAED))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: _assistantPurple,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.oil_barrel_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.configuration.headerTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                  ),
                ),
                Text(
                  widget.configuration.headerSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 11,
                    color: DunesColors.text3,
                  ),
                ),
              ],
            ),
          ),
          if (wide)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _HeaderAction(
                icon: Icons.add_comment_outlined,
                label: '新建对话',
                primary: true,
                onTap: _sending ? null : _newConversation,
              ),
            )
          else
            TextButton(
              onPressed: _sending ? null : _newConversation,
              style: TextButton.styleFrom(
                foregroundColor: _assistantPurple,
                padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '新建',
                style: DunesTypography.sans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _assistantPurple,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF1EDFF), Color(0xFFFAF9FF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2DCFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.configuration.welcomeTitle,
            style: DunesTypography.sans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF49338B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.configuration.welcomeBody,
            style: DunesTypography.sans(
              fontSize: 13,
              height: 1.55,
              color: DunesColors.text2,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final prompt in widget.configuration.welcomePrompts)
                _PromptChip(
                  label: prompt,
                  onTap: _sending || _connecting ? null : () => _send(prompt),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final wide = isWideChatLayout(context);
    final enabled = !_sending && !_connecting;
    final fontSize = wide ? 14.0 : 16.0;
    final fieldPadV = wide ? 12.0 : 10.0;
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          wide ? 16 : 10,
          wide ? 10 : 8,
          wide ? 16 : 10,
          wide ? 12 : 8,
        ),
        decoration: BoxDecoration(
          color: wide ? Colors.white : const Color(0xFFF7F7F7),
          border: const Border(top: BorderSide(color: Color(0xFFE8E8E8))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(wide ? 10 : 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(wide ? 10 : 8),
                    border: Border.all(color: const Color(0xFFE3DCEE)),
                  ),
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onKeyEvent: (node, event) =>
                        _onComposerKey(event, wide: wide, enabled: enabled),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      enabled: enabled,
                      minLines: 1,
                      maxLines: wide ? 6 : 4,
                      textAlignVertical: TextAlignVertical.center,
                      keyboardType: TextInputType.multiline,
                      textInputAction: wide
                          ? TextInputAction.newline
                          : TextInputAction.send,
                      textCapitalization: TextCapitalization.sentences,
                      cursorColor: _assistantPurple,
                      onTap: _jumpToEnd,
                      onSubmitted: !wide && enabled
                          ? (value) {
                              _send(value);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                _focus.requestFocus();
                              });
                            }
                          : null,
                      style: DunesTypography.sans(
                        fontSize: fontSize,
                        height: 1.4,
                        color: DunesColors.text,
                      ),
                      decoration: InputDecoration(
                        hintText: '输入你的问题…',
                        hintStyle: DunesTypography.sans(
                          fontSize: fontSize,
                          color: DunesColors.text3,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: fieldPadV,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final canSend = enabled && _controller.text.trim().isNotEmpty;
                return _ComposerSendButton(
                  wide: wide,
                  enabled: canSend,
                  sending: _sending,
                  onTap: canSend ? () => _send(_controller.text) : null,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _onComposerKey(
    KeyEvent event, {
    required bool wide,
    required bool enabled,
  }) {
    if (!wide || !enabled) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    final composing = _controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    _send(_controller.text);
    return KeyEventResult.handled;
  }
}

class _ComposerSendButton extends StatelessWidget {
  const _ComposerSendButton({
    required this.wide,
    required this.enabled,
    required this.sending,
    this.onTap,
  });

  final bool wide;
  final bool enabled;
  final bool sending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
    if (wide) {
      return Material(
        color: enabled || sending ? _assistantPurple : const Color(0xFFD4CFE6),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            height: 40 * scale,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        '发送',
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
    }
    final size = 40.0 * scale;
    return Material(
      color: enabled || sending ? _assistantPurple : const Color(0xFFD4CFE6),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: sending
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(
                  Icons.arrow_upward_rounded,
                  color: Colors.white,
                  size: 20,
                ),
        ),
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFD8D0FB)),
          ),
          child: Text(
            label,
            style: DunesTypography.sans(
              fontSize: 12,
              height: 1.25,
              color: onTap == null
                  ? DunesColors.text3
                  : const Color(0xFF5D43AE),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.primary,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? Colors.white : const Color(0xFF5D43AE);
    return Material(
      color: primary ? _assistantPurple : Colors.white,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: primary ? null : Border.all(color: const Color(0xFFD8D0FB)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: foreground),
              const SizedBox(width: 5),
              Text(
                label,
                style: DunesTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2DCFF)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF5D43AE)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: DunesTypography.sans(
                fontSize: 12,
                height: 1.4,
                color: const Color(0xFF5D43AE),
              ),
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: _assistantPurple,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel!,
                style: DunesTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.sizeOf(context).width *
              (isWideChatLayout(context) ? 0.55 : 0.78),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _assistantPurple,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: DunesTypography.sans(
            fontSize: 13,
            height: 1.45,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.text,
    required this.toolStatus,
    required this.busy,
  });

  final String text;
  final String toolStatus;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: _assistantPurple,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.oil_barrel_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth:
                  MediaQuery.sizeOf(context).width *
                  (isWideChatLayout(context) ? 0.62 : 0.82),
            ),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8EAED)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (toolStatus.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: Color(0xFF5D43AE),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            toolStatus,
                            style: DunesTypography.sans(
                              fontSize: 12,
                              color: const Color(0xFF5D43AE),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (text.isNotEmpty)
                  MarkdownBody(
                    data: text,
                    selectable: !busy,
                    softLineBreak: true,
                    styleSheet: _digitalAutoMdStyle(),
                    onTapLink: (label, href, title) {
                      final raw = (href ?? '').trim();
                      if (raw.isEmpty) return;
                      final uri = Uri.tryParse(raw);
                      if (uri == null) return;
                      launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                  )
                else if (busy)
                  Text(
                    '正在思考…',
                    style: DunesTypography.sans(
                      fontSize: 13,
                      color: DunesColors.text3,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

MarkdownStyleSheet _digitalAutoMdStyle() {
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
    em: DunesTypography.sans(
      fontSize: 13,
      color: DunesColors.text,
    ).copyWith(fontStyle: FontStyle.italic),
    code: DunesTypography.sans(
      fontSize: 12,
      color: DunesColors.text,
    ).copyWith(backgroundColor: const Color(0xFFF0F1F4)),
    codeblockDecoration: BoxDecoration(
      color: const Color(0xFFF0F1F4),
      borderRadius: BorderRadius.circular(8),
    ),
    listBullet: DunesTypography.sans(
      fontSize: 13,
      height: 1.55,
      color: DunesColors.text3,
    ),
    blockquote: DunesTypography.sans(
      fontSize: 13,
      height: 1.5,
      color: DunesColors.text3,
    ),
    blockquoteDecoration: const BoxDecoration(
      border: Border(left: BorderSide(color: _assistantPurple, width: 3)),
    ),
    a: DunesTypography.sans(
      fontSize: 13,
      color: const Color(0xFF5D43AE),
    ).copyWith(decoration: TextDecoration.underline),
    tableColumnWidth: const IntrinsicColumnWidth(),
    tableHead: DunesTypography.sans(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: DunesColors.text,
      height: 1.35,
    ),
    tableBody: DunesTypography.sans(
      fontSize: 12,
      color: DunesColors.text2,
      height: 1.35,
    ),
    tableBorder: TableBorder.all(color: const Color(0xFFE6E6EA), width: 0.5),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    tableHeadAlign: TextAlign.center,
  );
}
