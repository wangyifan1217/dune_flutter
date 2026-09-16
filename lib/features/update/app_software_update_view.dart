import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'app_release_notes.dart';

const _pageBg = Color(0xFFF3F4F6);
const _cardRadius = 18.0;
const _actionBlue = Color(0xFF007DFF);

/// HarmonyOS「软件更新」风格的内容区：品牌 Hero + 说明卡片。
class AppSoftwareUpdateBody extends StatelessWidget {
  const AppSoftwareUpdateBody({
    super.key,
    required this.versionName,
    required this.platformLabel,
    required this.notes,
    this.heroTag = '沙丘',
    this.heroSubTag = 'DUNES',
  });

  final String versionName;
  final String platformLabel;
  final ParsedReleaseNotes notes;
  final String heroTag;
  final String heroSubTag;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroCard(
          versionName: versionName,
          platformLabel: platformLabel,
          heroTag: heroTag,
          heroSubTag: heroSubTag,
        ),
        const SizedBox(height: 14),
        _NotesCard(notes: notes),
      ],
    );
  }
}

class AppSoftwareUpdateScaffold extends StatelessWidget {
  const AppSoftwareUpdateScaffold({
    super.key,
    required this.body,
    this.title = '软件更新',
    this.onBack,
    this.canPop = true,
    this.bottom,
  });

  final Widget body;
  final String title;
  final VoidCallback? onBack;
  final bool canPop;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: canPop,
      child: Material(
        color: _pageBg,
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: SizedBox(
                height: 52,
                child: NavigationToolbar(
                  leading: canPop
                      ? IconButton(
                          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                          icon: const Icon(
                            Icons.chevron_left_rounded,
                            size: 28,
                            color: Color(0xFF1A1A1A),
                          ),
                        )
                      : const SizedBox(width: 48),
                  middle: Text(
                    title,
                    style: DunesTypography.sans(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [body],
              ),
            ),
            ?bottom,
          ],
        ),
      ),
    );
  }
}

class AppSoftwareUpdateActionBar extends StatelessWidget {
  const AppSoftwareUpdateActionBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.progress,
    this.progressLabel,
    this.error,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final double? progress;
  final String? progressLabel;
  final String? error;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _pageBg,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(99),
                  color: _actionBlue,
                  backgroundColor: const Color(0xFFD6E6FA),
                ),
                const SizedBox(height: 8),
                if (progressLabel != null)
                  Text(
                    progressLabel!,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: DunesColors.text3,
                    ),
                  ),
                const SizedBox(height: 10),
              ],
              if (error != null) ...[
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: const Color(0xFFC62828),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280, minWidth: 200),
                  child: SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton(
                      onPressed: onPressed,
                      style: FilledButton.styleFrom(
                        backgroundColor: _actionBlue,
                        disabledBackgroundColor: _actionBlue.withValues(alpha: 0.45),
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        elevation: 0,
                      ),
                      child: Text(
                        label,
                        style: DunesTypography.sans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (secondaryLabel != null && onSecondary != null) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: busy ? null : onSecondary,
                  child: Text(
                    secondaryLabel!,
                    style: DunesTypography.sans(
                      fontSize: 14,
                      color: DunesColors.text3,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.versionName,
    required this.platformLabel,
    required this.heroTag,
    required this.heroSubTag,
  });

  final String versionName;
  final String platformLabel;
  final String heroTag;
  final String heroSubTag;

  @override
  Widget build(BuildContext context) {
    final version = versionName.trim().isEmpty ? '最新版本' : versionName.trim();
    final meta = [
      version,
      if (platformLabel.trim().isNotEmpty) platformLabel.trim(),
    ].join('  |  ');
    return Container(
      height: 188,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_cardRadius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF7F4FC),
            Color(0xFFE8E6F6),
            Color(0xFFD9E4F6),
          ],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -36,
            top: -48,
            child: Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.42),
              ),
            ),
          ),
          Positioned(
            left: -28,
            bottom: -52,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFB8C8E8).withValues(alpha: 0.28),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  heroTag,
                  style: DunesTypography.sans(
                    fontSize: 34,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2A2A2A),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 72,
                  height: 2,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  heroSubTag,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    letterSpacing: 3.2,
                    color: const Color(0xFF6B6B76),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  meta,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: const Color(0xFF6B6B76),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.notes});

  final ParsedReleaseNotes notes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notes.headline,
              style: DunesTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              notes.summary,
              style: DunesTypography.sans(
                fontSize: 14,
                height: 1.65,
                color: const Color(0xFF4A4A4A),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              '更新注意事项：',
              style: DunesTypography.sans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < notes.notices.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Text(
                '${i + 1}. ${notes.notices[i]}',
                style: DunesTypography.sans(
                  fontSize: 14,
                  height: 1.65,
                  color: const Color(0xFF4A4A4A),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
