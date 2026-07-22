import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';

const _themePurple = Color(0xFF7B5CD8);

/// 千机 Hub：与工作台一致的入口卡片布局（PC / APP 共用）。
class NativeQianjiHubPage extends StatelessWidget {
  const NativeQianjiHubPage({
    super.key,
    required this.onOpenCursorAccount,
    this.onOpenMeetingSupervise,
    this.session,
  });

  final VoidCallback onOpenCursorAccount;
  final VoidCallback? onOpenMeetingSupervise;
  final AuthSession? session;

  bool get _hasAccess =>
      session == null || session!.effectiveQianjiAccess;

  @override
  Widget build(BuildContext context) {
    if (!_hasAccess) {
      return _buildNoAccessView();
    }

    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  _QianjiHubSection(
                    title: '管理',
                    accent: _themePurple,
                    children: [
                      _QianjiHubTile(
                        title: 'Cursor账号监管',
                        subtitle: '账号与用量',
                        icon: Icons.manage_accounts_outlined,
                        color: _themePurple,
                        onTap: onOpenCursorAccount,
                      ),
                      _QianjiHubTile(
                        title: '会议纪要监管',
                        subtitle: '本人及下级',
                        icon: Icons.fact_check_outlined,
                        color: _themePurple,
                        onTap: onOpenMeetingSupervise,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoAccessView() {
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EEF7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE8EAED)),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  size: 28,
                  color: DunesColors.text3,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '暂无权限',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '当前账号未开通千机访问权限，如需使用请联系管理员。',
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text3,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QianjiHubTile {
  const _QianjiHubTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
}

class _QianjiHubSection extends StatelessWidget {
  const _QianjiHubSection({
    required this.title,
    required this.accent,
    required this.children,
  });

  final String title;
  final Color accent;
  final List<_QianjiHubTile> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final tile in children) _QianjiHubCard(tile: tile),
            ],
          ),
        ],
      ),
    );
  }
}

class _QianjiHubCard extends StatelessWidget {
  const _QianjiHubCard({required this.tile});

  final _QianjiHubTile tile;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8F7FB),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: tile.onTap,
        child: SizedBox(
          width: 132,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: tile.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(tile.icon, color: tile.color, size: 18),
                ),
                const SizedBox(height: 12),
                Text(
                  tile.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tile.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    color: DunesColors.text3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
