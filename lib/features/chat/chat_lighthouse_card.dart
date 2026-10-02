import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import '../lighthouse/lighthouse_shared_card_data.dart';
import '../lighthouse/lighthouse_message_card_layout.dart';
import '../lighthouse/native_lighthouse_page.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';

/// A real business card: identical lighthouse builders, gestures and charts.
class ChatLighthouseCard extends StatelessWidget {
  const ChatLighthouseCard({
    super.key,
    required this.session,
    required this.data,
  });
  final AuthSession session;
  final LighthouseSharedCardData data;
  @override
  Widget build(BuildContext context) => LighthouseMessageCardFrame(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Row(
            children: [
              Icon(
                Icons.bar_chart_rounded,
                size: 13,
                color: DunesColors.resolveNullable(context, Color(0xFF7565C7)),
              ),
              const SizedBox(width: 5),
              Text(
                '灯塔',
                style: TextStyle(
                  fontSize: 10,
                  color: DunesColors.resolveNullable(
                    context,
                    Color(0xFF6750A4),
                  ),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  data.range,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: DunesColors.resolveNullable(
                      context,
                      Color(0xFF696474),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        LighthouseEmbeddedCard(session: session, data: data),
      ],
    ),
  );
}

/// Uses the existing authenticated IM image pipeline for the captured card.
class ChatLighthouseLegacyImageCard extends StatelessWidget {
  const ChatLighthouseLegacyImageCard({
    super.key,
    required this.metadata,
    required this.child,
  });
  final Map metadata;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: DunesColors.resolve(
          context,
          const Color(0xFFE6E0F1),
          role: DunesColorRole.border,
        ),
      ),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '灯塔 · 卡片快照',
          style: TextStyle(
            fontSize: 10,
            color: DunesColors.resolveNullable(context, Color(0xFF6750A4)),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(
            metadata['title']?.toString() ?? '灯塔卡片',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          metadata['range']?.toString() ?? '',
          style: TextStyle(
            fontSize: 10,
            color: DunesColors.resolveNullable(context, Color(0xFF696474)),
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}
