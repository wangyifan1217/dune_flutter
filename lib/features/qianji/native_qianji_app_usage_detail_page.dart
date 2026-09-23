import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/analytics/usage_module_map.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import 'app_usage_models.dart';
import 'app_usage_service.dart';

const _themePurple = Color(0xFF7B5CD8);

class NativeQianjiAppUsageDetailPage extends StatefulWidget {
  const NativeQianjiAppUsageDetailPage({
    super.key,
    required this.session,
    required this.userId,
    required this.onBack,
    this.displayName = '',
    this.departmentName = '',
    this.from,
    this.to,
  });

  final AuthSession session;
  final int userId;
  final VoidCallback onBack;
  final String displayName;
  final String departmentName;
  final DateTime? from;
  final DateTime? to;

  @override
  State<NativeQianjiAppUsageDetailPage> createState() =>
      _NativeQianjiAppUsageDetailPageState();
}

class _NativeQianjiAppUsageDetailPageState
    extends State<NativeQianjiAppUsageDetailPage> {
  late final AppUsageService _service = AppUsageService(
    session: widget.session,
  );
  AppUsageUserDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _service.fetchUserDetail(
        userId: widget.userId,
        from: widget.from,
        to: widget.to,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _detail?.displayName.isNotEmpty == true
        ? _detail!.displayName
        : (widget.displayName.isNotEmpty ? widget.displayName : '使用明细');
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: widget.onBack,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_ios_new,
                            size: 14,
                            color: DunesColors.text2,
                          ),
                          SizedBox(width: 2),
                          Text(
                            '使用热力',
                            style: TextStyle(
                              fontSize: 13,
                              color: DunesColors.text2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _themePurple,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: _themePurple,
                onRefresh: _load,
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 160),
          Center(child: CircularProgressIndicator(color: _themePurple)),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Text(
            friendlyErrorText(_error, fallback: '加载失败，请稍后重试'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: DunesColors.text2),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: () => unawaited(_load()),
              child: const Text('重试'),
            ),
          ),
        ],
      );
    }
    final detail = _detail;
    if (detail == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: Text('暂无数据', style: TextStyle(color: DunesColors.text3))),
        ],
      );
    }
    final dept = detail.departmentName.isNotEmpty
        ? detail.departmentName
        : widget.departmentName;
    final days = detail.days;
    final maxDay = days.fold<int>(
      0,
      (m, e) => e.durationMs > m ? e.durationMs : m,
    );
    final pages = groupedUsageModules(detail.pages);
    final maxPage = pages.fold<int>(
      0,
      (m, e) => e.durationMs > m ? e.durationMs : m,
    );
    final topModule = pages.isNotEmpty
        ? pages.first.screenName
        : usageModuleLabel(detail.topModule, detail.topModuleName);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        Text(
          [
            if (dept.isNotEmpty) dept,
            '停留 ${formatUsageStay(detail.durationMs)}',
          ].join(' · '),
          style: const TextStyle(fontSize: 13, color: DunesColors.text2),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Stat(label: '会话', value: '${detail.sessionCount}次'),
            const SizedBox(width: 8),
            _Stat(label: '打开', value: '${detail.pv}次'),
            const SizedBox(width: 8),
            _Stat(
              label: '最常用',
              value: topModule.isEmpty ? '-' : topModule,
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          '功能停留',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF261D38),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '携程、薪人薪事和各免登应用分开统计，其它按功能汇总',
          style: TextStyle(fontSize: 12, color: DunesColors.text3),
        ),
        const SizedBox(height: 10),
        if (pages.isEmpty)
          const Text('暂无使用数据', style: TextStyle(color: DunesColors.text3))
        else
          for (final page in pages)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PageBar(page: page, maxDuration: maxPage),
            ),
        const SizedBox(height: 12),
        const Text(
          '每日使用',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF261D38),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '不含后台挂机时间',
          style: TextStyle(fontSize: 12, color: DunesColors.text3),
        ),
        const SizedBox(height: 12),
        if (days.isEmpty)
          const Text('暂无每日数据', style: TextStyle(color: DunesColors.text3))
        else
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _DayCol(day: day, maxDuration: maxDay),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEDE8F5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: DunesColors.text3),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _themePurple,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageBar extends StatelessWidget {
  const _PageBar({required this.page, required this.maxDuration});

  final AppUsagePageStay page;
  final int maxDuration;

  @override
  Widget build(BuildContext context) {
    final ratio = maxDuration <= 0 ? 0.0 : page.durationMs / maxDuration;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                page.screenName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF261D38),
                ),
              ),
            ),
            Text(
              formatUsageStay(page.durationMs),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _themePurple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.04, 1),
            minHeight: 6,
            backgroundColor: const Color(0xFFF1EBF9),
            color: _themePurple,
          ),
        ),
      ],
    );
  }
}

class _DayCol extends StatelessWidget {
  const _DayCol({required this.day, required this.maxDuration});

  final AppUsageDayStay day;
  final int maxDuration;

  @override
  Widget build(BuildContext context) {
    final ratio = maxDuration <= 0 ? 0.0 : day.durationMs / maxDuration;
    final label = day.date.length >= 10 ? day.date.substring(5) : day.date;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: ratio.clamp(0.08, 1),
              widthFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color.lerp(
                    const Color(0xFFE8DDF8),
                    _themePurple,
                    ratio.clamp(0.15, 1),
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: DunesColors.text3),
        ),
      ],
    );
  }
}
