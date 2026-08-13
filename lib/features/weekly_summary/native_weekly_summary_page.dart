import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../chat/assistant_transcript_support.dart';
import '../chat/chat_widgets.dart';
import '../chat/gallery_save.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import '../desktop/windows_desktop_tray.dart';
import '../shell/dunes_toast.dart';
import 'weekly_summary_card.dart';
import 'weekly_summary_models.dart';

class NativeWeeklySummaryPage extends StatefulWidget {
  const NativeWeeklySummaryPage({
    super.key,
    required this.session,
    required this.conversationHint,
    this.showBackButton = true,
    this.autoMarkRead = true,
    this.onBack,
    this.onConversationRead,
  });

  final AuthSession session;
  final NativeConversation conversationHint;
  final bool showBackButton;
  final bool autoMarkRead;
  final VoidCallback? onBack;
  final ValueChanged<int>? onConversationRead;

  @override
  State<NativeWeeklySummaryPage> createState() =>
      _NativeWeeklySummaryPageState();
}

class _NativeWeeklySummaryPageState extends State<NativeWeeklySummaryPage> {
  late final ConversationService _service;
  final _scroll = ScrollController();
  final List<NativeChatMessage> _messages = [];
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = false;
  bool _awayFromLatest = false;
  String? _error;
  StreamSubscription<ConversationRealtimeEvent>? _rtSub;
  Timer? _rtDebounce;

  int get _convId => widget.conversationHint.id;

  @override
  void initState() {
    super.initState();
    _service = ConversationService(session: widget.session);
    _scroll.addListener(_onScroll);
    _bootstrap();
    final realtime = ConversationRealtimeHub.instance.of(widget.session);
    unawaited(realtime.connect());
    _rtSub = realtime.events.listen(_onRealtime);
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    _rtDebounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(NativeWeeklySummaryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.autoMarkRead && widget.autoMarkRead) {
      unawaited(_markReadIfViewing());
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final convId = _convId;
      if (convId <= 0) {
        throw Exception('一周小结会话无效');
      }
      unawaited(
        ConversationRealtimeHub.instance
            .of(widget.session)
            .ensureConversationSubscription(convId),
      );
      await _markReadIfViewing();
      await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToLatestOnEnter();
    }
  }

  Future<void> _reload({bool silent = false}) async {
    try {
      final page = await _service.fetchMessagePage(_convId);
      if (!mounted) return;
      setState(() {
        final next = silent
            ? mergeLatestAssistantMessages(
                current: List<NativeChatMessage>.from(_messages),
                latest: page.items,
              )
            : page.items;
        _messages
          ..clear()
          ..addAll(next);
        if (!silent) {
          _hasMore = page.hasMore;
          _error = null;
        }
      });
      if (!silent) {
        _scrollToLatestOnEnter();
      } else if (!_awayFromLatest) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpBottom());
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() => _error = friendlyErrorText(e));
      }
    }
  }

  Future<void> _markReadIfViewing() async {
    if (!widget.autoMarkRead || windowsTrayIsWindowInactive()) return;
    final id = _convId;
    if (id <= 0) return;
    await _service.markConversationRead(id);
    widget.onConversationRead?.call(id);
  }

  void _onRealtime(ConversationRealtimeEvent event) {
    if (event.conversationId != _convId) return;
    if (event.type == 'message' || event.type == 'conversation_updated') {
      _rtDebounce?.cancel();
      _rtDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        unawaited(_reload(silent: true));
        unawaited(_markReadIfViewing());
      });
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final away = assistantIsAwayFromLatest(pos);
    if (away != _awayFromLatest && mounted) {
      setState(() => _awayFromLatest = away);
    }
    if (assistantShouldLoadOlder(
      hasMore: _hasMore,
      loadingOlder: _loadingOlder,
      pos: pos,
    )) {
      unawaited(_loadOlder());
    }
  }

  void _scrollToLatestOnEnter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpBottom(markLatest: true);
      Future<void>.delayed(
        const Duration(milliseconds: 80),
        () => _jumpBottom(markLatest: true),
      );
      Future<void>.delayed(
        const Duration(milliseconds: 240),
        () => _jumpBottom(markLatest: true),
      );
    });
  }

  void _jumpBottom({bool animate = false, bool markLatest = false}) {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (animate) {
      _scroll.animateTo(
        max,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(max);
    }
    if (markLatest && _awayFromLatest && mounted) {
      setState(() => _awayFromLatest = false);
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore || _messages.isEmpty || _convId <= 0) {
      return;
    }
    setState(() => _loadingOlder = true);
    final firstId = _messages.first.id;
    final oldMax = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final oldPixels = _scroll.hasClients ? _scroll.position.pixels : 0.0;
    try {
      final page = await _service.fetchMessagePage(_convId, before: firstId);
      if (!mounted) return;
      final current = List<NativeChatMessage>.from(_messages);
      setState(() {
        _messages
          ..clear()
          ..addAll(
            mergeOlderAssistantMessages(current: current, older: page.items),
          );
        _hasMore = page.hasMore;
        _loadingOlder = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.jumpTo(
          assistantOlderScrollRestore(
            oldPixels: oldPixels,
            oldMax: oldMax,
            newMax: _scroll.position.maxScrollExtent,
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _openDetail(WeeklySummaryShare data) async {
    await showWeeklySummaryDetailSheet(
      context: context,
      session: widget.session,
      data: data,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ChatConvHeader(
              title: '一周小结',
              subtitle: '每周五 18:00 送达',
              onBack: widget.onBack ?? () => Navigator.maybePop(context),
              showBackButton: widget.showBackButton,
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: DunesColors.text2),
                      ),
                    )
                  : _messages.isEmpty
                  ? const Center(
                      child: Text(
                        '周五下午 6 点会送达本周小结',
                        style: TextStyle(color: DunesColors.text3),
                      ),
                    )
                  : Stack(
                      children: [
                        ListView.builder(
                          controller: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                          itemCount:
                              _messages.length + (_loadingOlder ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_loadingOlder && index == 0) {
                              return const Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            }
                            final m =
                                _messages[_loadingOlder ? index - 1 : index];
                            final data =
                                WeeklySummaryShare.fromPayload(m.payload);
                            final time = InboxFormat.msgTimeLabel(m.createdAt);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                children: [
                                  if (time.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        time,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: DunesColors.text3,
                                        ),
                                      ),
                                    ),
                                  if (data != null)
                                    GestureDetector(
                                      onTap: () => unawaited(_openDetail(data)),
                                      child: WeeklySummaryPoster(
                                        data: data,
                                        compact: true,
                                      ),
                                    )
                                  else
                                    Text(
                                      m.bodyText,
                                      style: const TextStyle(
                                        color: DunesColors.text2,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                        if (_awayFromLatest)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 12,
                            child: AssistantBackToLatestChip(
                              onTap: () =>
                                  _jumpBottom(animate: true, markLatest: true),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showWeeklySummaryDetailSheet({
  required BuildContext context,
  required AuthSession session,
  required WeeklySummaryShare data,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WeeklySummaryDetailSheet(session: session, data: data),
  );
}

class _WeeklySummaryDetailSheet extends StatefulWidget {
  const _WeeklySummaryDetailSheet({
    required this.session,
    required this.data,
  });

  final AuthSession session;
  final WeeklySummaryShare data;

  @override
  State<_WeeklySummaryDetailSheet> createState() =>
      _WeeklySummaryDetailSheetState();
}

class _WeeklySummaryDetailSheetState extends State<_WeeklySummaryDetailSheet> {
  final GlobalKey _posterKey = GlobalKey();
  bool _busy = false;

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capturePoster();
      final name = '一周小结-${widget.data.rangeLabel.replaceAll('.', '-')}.png';
      if (isDesktopCommOnly) {
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'PNG', extensions: <String>['png']),
          ],
        );
        if (location == null) return;
        final file = XFile.fromData(
          bytes,
          mimeType: 'image/png',
          name: name,
        );
        await file.saveTo(location.path);
      } else {
        await saveImageToGallery(bytes, name);
      }
      if (mounted) showDunesToast(context, '已保存');
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e, fallback: '保存失败'),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forward() async {
    if (_busy) return;
    final service = ConversationService(session: widget.session);
    final ids = await showConversationMultiPickerSheet(
      context: context,
      service: service,
      title: '转发给',
    );
    if (ids == null || ids.isEmpty) return;
    setState(() => _busy = true);
    try {
      final payload = widget.data.toPayload();
      final body = widget.data.previewText;
      for (final id in ids) {
        await service.sendMessageRaw(
          conversationId: id,
          kind: 'WEEKLY_SUMMARY',
          bodyText: body,
          payload: payload,
        );
      }
      if (mounted) {
        showDunesToast(context, '已转发');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e, fallback: '转发失败'),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<ui.Image> _posterImage() async {
    final boundary =
        _posterKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw Exception('海报尚未渲染');
    }
    return boundary.toImage(pixelRatio: 3);
  }

  Future<Uint8List> _capturePoster() async {
    final image = await _posterImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw Exception('截图失败');
    return bytes.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: DunesColors.bgApp,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '一周小结',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              child: Center(
                child: RepaintBoundary(
                  key: _posterKey,
                  child: WeeklySummaryPoster(
                    data: widget.data,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => unawaited(_save()),
                    icon: const Icon(Icons.photo_outlined, size: 18),
                    label: Text(isDesktopCommOnly ? '保存图片' : '保存相册'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => unawaited(_forward()),
                    icon: const Icon(Icons.shortcut_rounded, size: 18),
                    label: const Text('转发'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
