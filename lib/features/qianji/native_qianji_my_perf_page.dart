import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'qianji_perf_shared.dart';

/// 我的绩效静态页（原生 Flutter）。
class NativeQianjiMyPerfPage extends StatefulWidget {
  const NativeQianjiMyPerfPage({
    super.key,
    required this.onBack,
    this.onOpenTeamPerf,
  });

  final VoidCallback onBack;
  final VoidCallback? onOpenTeamPerf;

  @override
  State<NativeQianjiMyPerfPage> createState() => _NativeQianjiMyPerfPageState();
}

class _NativeQianjiMyPerfPageState extends State<NativeQianjiMyPerfPage> {
  QianjiPerfFilter _filter = QianjiPerfFilter.all;

  List<QianjiMonthlyPerf> get _items {
    final all = QianjiPerfCatalog.monthlyItems;
    if (_filter == QianjiPerfFilter.all) return all;
    return all
        .where((e) => e.filterTags.contains(_filter))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            QianjiPerfNavBar(
              title: '我的绩效',
              onBack: widget.onBack,
              action: '2026',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  QianjiPerfOverviewCard(
                    label: '月度考核 · 本人视图',
                    period: '张三 · 前端开发',
                    stats: QianjiPerfCatalog.myStats,
                    linkLabel: '团队考核 ›',
                    onLinkTap: widget.onOpenTeamPerf,
                  ),
                  const SizedBox(height: 12),
                  QianjiPerfFilterChips(
                    selected: _filter,
                    onSelected: (v) => setState(() => _filter = v),
                    options: const [
                      (QianjiPerfFilter.all, '全部'),
                      (QianjiPerfFilter.published, '已公示'),
                      (QianjiPerfFilter.waitManager, '待主管评'),
                      (QianjiPerfFilter.waitSelf, '待自评'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  QianjiPerfSectionCard(
                    title: '2026 年',
                    trailing: '${items.length} 条',
                    child: items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Text(
                                '当前筛选暂无记录',
                                style: DunesTypography.sans(
                                  fontSize: 13,
                                  color: DunesColors.text3,
                                ),
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              for (final item in items) _MonthRow(item: item),
                            ],
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

class _MonthRow extends StatelessWidget {
  const _MonthRow({required this.item});

  final QianjiMonthlyPerf item;

  @override
  Widget build(BuildContext context) {
    final muted = item.running;
    return Opacity(
      opacity: muted ? 0.8 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: muted
                    ? DunesColors.bgSoft
                    : item.level.startsWith('B')
                        ? DunesColors.amberSoft
                        : QianjiPerfTheme.purpleSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                item.monthLabel,
                style: DunesTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: muted
                      ? DunesColors.text3
                      : item.level.startsWith('B')
                          ? DunesColors.amber
                          : QianjiPerfTheme.purple,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: DunesTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.meta,
                    style: DunesTypography.sans(
                      fontSize: 11,
                      color: DunesColors.text3,
                    ),
                  ),
                ],
              ),
            ),
            if (item.running)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: DunesColors.amberSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '进行中',
                  style: DunesTypography.sans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.amber,
                  ),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    item.score,
                    style: DunesTypography.sans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: QianjiPerfTheme.purple,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: item.level.startsWith('B')
                          ? DunesColors.amberSoft
                          : QianjiPerfTheme.purpleSoft,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      item.level,
                      style: DunesTypography.sans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: item.level.startsWith('B')
                            ? DunesColors.amber
                            : QianjiPerfTheme.purple,
                      ),
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
