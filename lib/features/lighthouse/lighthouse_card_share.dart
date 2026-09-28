import 'package:flutter/material.dart';

import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../conversation/conversation_service.dart';
import 'lighthouse_feedback.dart';
import 'lighthouse_shared_card_data.dart';

/// Places the forwarding icon in a slot INSIDE the card supplied by its builder.
class LighthouseShareableCard extends StatefulWidget {
  const LighthouseShareableCard({
    super.key,
    required this.session,
    required this.title,
    required this.rangeLabel,
    this.child,
    this.builder,
    this.data,
    this.previewBuilder,
    this.compact = false,
    this.serviceFactory,
  }) : assert(child != null || builder != null);
  final AuthSession session;
  final String title;
  final String rangeLabel;
  final Widget? child;
  final Widget Function(Widget icon)? builder;
  final LighthouseSharedCardData Function()? data;
  final Widget Function(LighthouseSharedCardData data)? previewBuilder;
  final bool compact;
  @visibleForTesting
  final ConversationService Function()? serviceFactory;
  @override
  State<LighthouseShareableCard> createState() =>
      _LighthouseShareableCardState();
}

class _LighthouseShareableCardState extends State<LighthouseShareableCard> {
  bool _busy = false;
  Future<void> _forward() async {
    if (_busy) return;
    setState(() => _busy = true);
    LighthouseFeedback.instance.play(LighthouseFeedbackKind.share);
    ConversationService? service;
    try {
      final data = widget.data?.call();
      if (data == null) throw StateError('卡片数据尚未就绪，请稍后重试');
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('转发灯塔卡片'),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LighthouseSharingScope(
                    enabled: false,
                    child:
                        widget.previewBuilder?.call(data) ??
                        Text(data.fallbackText),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      '发送可交互卡片，接收人可展开指标、趋势和细分。日期和金额保持本次分享口径，请确认数据适合所选会话。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('选择会话'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      service =
          widget.serviceFactory?.call() ??
          ConversationService(session: widget.session);
      final ids = await showConversationMultiPickerSheet(
        context: context,
        service: service,
        title: '选择会话并确认转发',
        maxCount: 1,
      );
      if (ids == null || ids.isEmpty || !mounted) return;
      // Same structured TEXT payload mechanism as the KPI business card.
      // No PNG upload, URL or credentials; recipient permissions stay unchanged.
      await service.sendText(
        ids.single,
        data.fallbackText,
        payload: {'lighthouseCard': data.toJson()},
      );
      if (!mounted) return;
      LighthouseFeedback.instance.play(LighthouseFeedbackKind.success);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('卡片已转发')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('转发失败：${friendlyErrorText(error)}')),
        );
      }
    } finally {
      service?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = LighthouseSharingScope.enabledOf(context);
    final icon = SizedBox(
      width: widget.compact ? 24 : 28,
      height: widget.compact ? 24 : 28,
      child: enabled
          ? IconButton(
              tooltip: '转发卡片',
              onPressed: _busy ? null : _forward,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              color: const Color(0xFF6750A4),
              icon: _busy
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  : const Icon(Icons.ios_share_rounded, size: 15),
            )
          : null,
    );
    if (widget.builder != null) return widget.builder!(icon);
    return Stack(
      children: [
        widget.child!,
        Positioned(top: 4, right: 4, child: icon),
      ],
    );
  }
}

class LighthouseSharingScope extends InheritedWidget {
  const LighthouseSharingScope({
    super.key,
    required this.enabled,
    required super.child,
  });
  final bool enabled;
  static bool enabledOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<LighthouseSharingScope>()
          ?.enabled ??
      true;
  @override
  bool updateShouldNotify(LighthouseSharingScope oldWidget) =>
      enabled != oldWidget.enabled;
}
