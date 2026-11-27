import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'lighthouse_period_bar.dart';
import 'lighthouse_ledger_card_v2.dart';

/// 灯塔中石化受限视图：服务端只返回该供给方的规模数据。
class PartnerSinopecPage extends StatefulWidget {
  const PartnerSinopecPage({
    super.key,
    required this.session,
    required this.onBack,
    this.client,
  });
  final AuthSession session;
  final VoidCallback onBack;
  @visibleForTesting
  final http.Client? client;

  @override
  State<PartnerSinopecPage> createState() => _PartnerSinopecPageState();
}

class _PartnerSinopecPageState extends State<PartnerSinopecPage> {
  static const _periods = ['day', 'week', 'month', 'quarter', 'year'];
  DateTime _date = DateTime.now();
  int _selectedPeriod = 0;
  late Future<Map<String, dynamic>> _data = _load();

  String _dateText(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<Map<String, dynamic>> _load() async {
    final base = widget.session.apiBase.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/lighthouse/partner/sinopec-scale').replace(
      queryParameters: {
        'date': _dateText(_date),
        'period': _periods[_selectedPeriod],
      },
    );
    final headers = {'Authorization': 'Bearer ${widget.session.token}'};
    final response =
        await (widget.client?.get(uri, headers: headers) ??
                http.get(uri, headers: headers))
            .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('数据暂时不可用（${response.statusCode}）');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  void _reload() => setState(() => _data = _load());

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) {
      setState(() {
        _date = selected;
        _data = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: BackButton(onPressed: widget.onBack),
      title: const Text('灯塔 · 中石化'),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: LhPeriodBar(
            labels: const ['日', '周', '月', '季', '年'],
            selectedIndex: _selectedPeriod,
            baseTextStyle:
                Theme.of(context).textTheme.bodyMedium ??
                const TextStyle(fontSize: 14),
            onTap: (index) => setState(() {
              _selectedPeriod = index;
              _data = _load();
            }),
          ),
        ),
        TextButton.icon(
          onPressed: _selectDate,
          icon: const Icon(Icons.calendar_today_outlined, size: 17),
          label: Text(_dateText(_date)),
        ),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('数据加载失败，请稍后重试'),
                      TextButton(onPressed: _reload, child: const Text('重试')),
                    ],
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              final details = (data['details'] as List? ?? const [])
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList();
              final groups = <String, List<Map<String, dynamic>>>{};
              for (final item in details) {
                groups.putIfAbsent('${item['province']}', () => []).add(item);
              }
              String value(num amount) => amount.toStringAsFixed(2);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  Text(
                    '${data['label'] ?? ''}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('WOA'),
                                Text(
                                  value((data['woa'] as num?) ?? 0),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('GMV'),
                                Text(
                                  value((data['gmv'] as num?) ?? 0),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '标签二 · 中石化',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (groups.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('当前周期暂无数据'),
                      ),
                    ),
                  for (final group in groups.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: LighthouseLedgerCardV2(
                          name: group.key,
                          meta: '供给方 · 中石化',
                          profit: LhCardKpi(
                            label: 'WOA',
                            number: value(
                              group.value.fold<num>(
                                0,
                                (sum, item) =>
                                    sum + ((item['woa'] as num?) ?? 0),
                              ),
                            ),
                          ),
                          margin: LhCardKpi(
                            label: 'GMV',
                            number: value(
                              group.value.fold<num>(
                                0,
                                (sum, item) =>
                                    sum + ((item['gmv'] as num?) ?? 0),
                              ),
                            ),
                          ),
                          cells: const [],
                          linkText: '产品明细',
                          onOpenDetail: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (sheetContext) => SafeArea(
                              child: SizedBox(
                                height:
                                    MediaQuery.sizeOf(sheetContext).height * .7,
                                child: Column(
                                  children: [
                                    ListTile(
                                      title: Text('${group.key} · 产品明细'),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.close),
                                        onPressed: () =>
                                            Navigator.pop(sheetContext),
                                      ),
                                    ),
                                    Expanded(
                                      child: ListView(
                                        children: [
                                          for (final item in group.value)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 5,
                                                  ),
                                              child: Card(
                                                child: LighthouseLedgerCardV2(
                                                  name: '${item['product']}',
                                                  isChild: true,
                                                  meta: '中石化',
                                                  profit: LhCardKpi(
                                                    label: 'WOA',
                                                    number: value(
                                                      (item['woa'] as num?) ??
                                                          0,
                                                    ),
                                                  ),
                                                  margin: LhCardKpi(
                                                    label: 'GMV',
                                                    number: value(
                                                      (item['gmv'] as num?) ??
                                                          0,
                                                    ),
                                                  ),
                                                  cells: const [],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}
