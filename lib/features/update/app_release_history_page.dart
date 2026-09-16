import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/dunes_theme.dart';
import 'app_release_notes.dart';
import 'app_update_dialog.dart';
import 'app_update_service.dart';

/// 「我的」中的发版历史：仅展示当前运行平台对应的记录。
class AppReleaseHistoryPage extends StatefulWidget {
  const AppReleaseHistoryPage({super.key});

  @override
  State<AppReleaseHistoryPage> createState() => _AppReleaseHistoryPageState();
}

class _AppReleaseHistoryPageState extends State<AppReleaseHistoryPage> {
  bool _loading = true;
  String? _error;
  List<AppReleaseHistoryItem> _items = const [];
  String _currentVersion = '';
  int _currentCode = 0;

  String get _platformLabel => AppUpdateService.platformDisplayName();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await PackageInfo.fromPlatform();
      final items = await AppUpdateService.instance.fetchHistory();
      if (!mounted) return;
      setState(() {
        _currentVersion = info.version.trim();
        _currentCode = int.tryParse(info.buildNumber.trim()) ?? 0;
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '加载发版历史失败，请稍后重试';
        _loading = false;
      });
    }
  }

  void _openItem(AppReleaseHistoryItem item) {
    final newer = item.versionCode > _currentCode ||
        (item.versionCode == _currentCode &&
            item.versionName.trim().isNotEmpty &&
            item.versionName.trim() != _currentVersion);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppSoftwareUpdatePage(
          result: item.toCheckResult(updateAvailable: newer),
          showInstallAction: newer && item.downloadUrl.trim().isNotEmpty,
          title: '软件更新',
        ),
      ),
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final local = time.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}  ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: DunesTheme.light(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF3F4F6),
          foregroundColor: const Color(0xFF1A1A1A),
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
          ),
          title: Text(
            '发版历史',
            style: DunesTypography.sans(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          centerTitle: true,
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: TextButton(onPressed: _load, child: Text(_error!)),
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        _CurrentVersionCard(
          platformLabel: _platformLabel,
          versionName: _currentVersion,
        ),
        const SizedBox(height: 16),
        Text(
          '$_platformLabel 版本记录',
          style: DunesTypography.sans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: DunesColors.text2,
          ),
        ),
        const SizedBox(height: 8),
        if (_items.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '暂无 $_platformLabel 发版记录',
              style: DunesTypography.sans(
                fontSize: 14,
                color: DunesColors.text3,
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _items.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  _HistoryTile(
                    item: _items[i],
                    current: _isCurrent(_items[i]),
                    timeText: _formatTime(_items[i].createdAt),
                    onTap: () => _openItem(_items[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  bool _isCurrent(AppReleaseHistoryItem item) {
    if (_currentCode > 0 && item.versionCode == _currentCode) return true;
    return item.versionName.trim() == _currentVersion &&
        _currentVersion.isNotEmpty;
  }
}

class _CurrentVersionCard extends StatelessWidget {
  const _CurrentVersionCard({
    required this.platformLabel,
    required this.versionName,
  });

  final String platformLabel;
  final String versionName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFF0ECF6), Color(0xFFE7E2F2), Color(0xFFD9E4F6)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.system_update_alt_rounded,
              color: Color(0xFF5B4A9A),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前 $platformLabel 版本',
                  style: DunesTypography.sans(
                    fontSize: 12,
                    color: DunesColors.text2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  versionName.isEmpty ? '未知' : versionName,
                  style: DunesTypography.sans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
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

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.item,
    required this.current,
    required this.timeText,
    required this.onTap,
  });

  final AppReleaseHistoryItem item;
  final bool current;
  final String timeText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parsed = parseReleaseNotes(item.releaseNotes);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.versionName.isEmpty
                                ? '构建 ${item.versionCode}'
                                : item.versionName,
                            style: DunesTypography.sans(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1A1A1A),
                            ),
                          ),
                        ),
                        if (current) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F1FF),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '当前',
                              style: DunesTypography.sans(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF007DFF),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      parsed.headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DunesTypography.sans(
                        fontSize: 13,
                        color: DunesColors.text2,
                      ),
                    ),
                    if (timeText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        timeText,
                        style: DunesTypography.sans(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFB0B0B0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
