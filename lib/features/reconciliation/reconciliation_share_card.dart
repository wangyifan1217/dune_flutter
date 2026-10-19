import 'package:flutter/material.dart';

import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../conversation/conversation_service.dart';
import 'tag2_entity_models.dart';
import 'tag3_daily_models.dart';

Map<String, dynamic> buildReconciliationSharePayload({
  required Tag3DailySnapshot snapshot,
  required String asOfDate,
}) {
  final rows = <Map<String, dynamic>>[];
  for (final row in snapshot.rows) {
    if (row.isMonthCumulative) continue;
    final people = <Map<String, dynamic>>[];
    final assignee = snapshot.assigneeFor(row.rowKey);
    final lanes = tag3DailyAuditLanes(
      row: row,
      assignee: assignee,
      comments: snapshot.commentsFor(row),
    );
    for (final lane in lanes) {
      final assigned = lane.role == '业务'
          ? assignee?.businessUsers ?? const <Tag3DailyPerson>[]
          : assignee?.operationUsers ?? const <Tag3DailyPerson>[];
      for (final person in assigned) {
        final name = person.name.trim();
        if (name.isEmpty) continue;
        people.add({
          'id': person.userId,
          'role': lane.role,
          'name': name,
          'confirmed': lane.done,
        });
      }
    }
    for (final comment in snapshot.commentsFor(row)) {
      final name = comment.userName.trim();
      if (name.isEmpty) continue;
      final role = comment.stage == 'BUSINESS'
          ? '业务'
          : comment.stage == 'OPERATION' ? '运营' : '参与人';
      if (people.any((person) => person['name'] == name && person['role'] == role)) continue;
      people.add({'role': role, 'name': name, 'confirmed': comment.isConfirm});
    }
    rows.add({
      'channel': row.channelCategoryL1Name,
      'project': row.projectName,
      'period': row.periodLabel,
      'periodCode': row.period,
      'statDate': row.statDateDay,
      'paymentTerm': row.paymentTerm,
      'salesAmount': row.salesAmount,
      'salesScale': row.salesScale,
      'profitAmount': row.profitAmount,
      'cashReceivableAmount': row.cashReceivableAmount,
      'confirmed': lanes.every((lane) => lane.done),
      'people': people,
      'opinions': [
        for (final comment in snapshot.commentsFor(row))
          if (comment.isOpinion) comment.body,
      ],
    });
  }
  return {
    'reconciliationCard': {'version': 1, 'date': asOfDate, 'rows': rows},
  };
}

Map<String, dynamic> buildTag2SharePayload({
  required Tag2EntitySnapshot snapshot,
  required String asOfDate,
}) {
  final rows = <Map<String, dynamic>>[];
  for (final row in snapshot.rows) {
    if (row.isTotal) continue;
    final status = row.confirmationStatus;
    final comments = snapshot.commentsFor(row.rowKey);
    String names(String raw, String stage) {
      if (raw.trim().isNotEmpty) return raw.trim();
      final fromHistory = <String>{
        for (final comment in comments)
          if (comment.stage == stage && comment.userName.trim().isNotEmpty)
            comment.userName.trim(),
      };
      if (fromHistory.isNotEmpty) return fromHistory.join('、');
      if ((stage == 'BUSINESS' && status == 'WAIT_BUSINESS') ||
          (stage == 'OPERATION' && status == 'WAIT_OPERATION')) {
        return row.currentHandlers.trim();
      }
      return '';
    }
    final businessDone = status.isNotEmpty
        ? status == 'WAIT_OPERATION' || status == 'ALL_CONFIRMED' || status == 'CONFIRMED'
        : comments.any((comment) => comment.isConfirm && comment.stage == 'BUSINESS');
    final operationDone = status.isNotEmpty
        ? status == 'ALL_CONFIRMED' || status == 'CONFIRMED'
        : comments.any((comment) => comment.isConfirm && comment.stage == 'OPERATION');
    final people = <Map<String, dynamic>>[];
    for (final lane in [
      (role: '业务', names: names(row.businessBy, 'BUSINESS'), done: businessDone),
      (role: '运营', names: names(row.operationBy, 'OPERATION'), done: operationDone),
    ]) {
      for (final name in lane.names.split(RegExp(r'[、，,;；]'))) {
        if (name.trim().isEmpty) continue;
        people.add({'role': lane.role, 'name': name.trim(), 'confirmed': lane.done});
      }
    }
    final subject = [row.counterpartyName, row.ourEntityName]
        .where((value) => value.trim().isNotEmpty).join(' · ');
    String amountOf(String label) {
      for (final amount in row.amounts) {
        if (amount.label.trim().contains(label)) return amount.display.trim();
      }
      return '';
    }
    rows.add({
      'channel': row.provinceName.trim().isEmpty ? '未标注省份' : row.provinceName.trim(),
      'project': subject.isEmpty ? row.rowKey : subject,
      'period': row.supplierName.trim().isEmpty ? '主体核对' : row.supplierName.trim(),
      'periodCode': 'ENTITY',
      'confirmed': operationDone,
      'people': people,
      'fundsTotal': amountOf('资金合计'),
      'endingPrepayment': amountOf('期末预付款余额'),
      'opinions': [for (final comment in comments) if (comment.isOpinion || comment.isReject) comment.displayBody],
    });
  }
  return {
    'reconciliationCard': {
      'version': 1,
      'date': asOfDate,
      'subtitle': '标签二 · 按主体核对 · 对账确认进度',
      'groupLabel': '省份',
      'itemLabel': '主体',
      'unitLabel': '记录',
      'rows': rows,
    },
  };
}

class ReconciliationShareAction extends StatefulWidget {
  const ReconciliationShareAction({
    super.key,
    required this.session,
    this.snapshot,
    this.tag2Snapshot,
    required this.asOfDate,
  }) : assert(snapshot != null || tag2Snapshot != null);
  final AuthSession session;
  final Tag3DailySnapshot? snapshot;
  final Tag2EntitySnapshot? tag2Snapshot;
  final String asOfDate;
  @override
  State<ReconciliationShareAction> createState() =>
      _ReconciliationShareActionState();
}

class _ReconciliationShareActionState extends State<ReconciliationShareAction> {
  bool _busy = false;
  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final payload = widget.tag2Snapshot != null
          ? buildTag2SharePayload(snapshot: widget.tag2Snapshot!, asOfDate: widget.asOfDate)
          : buildReconciliationSharePayload(snapshot: widget.snapshot!, asOfDate: widget.asOfDate);
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          title: const Text('转发日清月结情况汇报'),
          content: ReconciliationSharePreview(
            payload: payload['reconciliationCard'] as Map<String, dynamic>,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('选择会话'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final service = ConversationService(session: widget.session);
      try {
        final ids = await showConversationMultiPickerSheet(
          context: context,
          service: service,
          title: '选择群聊并转发',
          maxCount: 10,
        );
        if (ids == null || ids.isEmpty) return;
        for (final id in ids) {
          await service.sendText(
            id,
            '日清月结情况汇报｜${widget.asOfDate}',
            payload: payload,
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('卡片已转发')));
        }
      } finally {
        service.close();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('转发失败：${friendlyErrorText(e)}')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '转发日清月结卡片',
    onPressed: _busy ? null : _share,
    icon: _busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.ios_share_rounded),
  );
}

class ReconciliationSharePreview extends StatelessWidget {
  const ReconciliationSharePreview({super.key, required this.payload});
  final Map<String, dynamic> payload;
  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 48).clamp(220.0, 380.0);
    return SizedBox(
      width: width,
      height: MediaQuery.sizeOf(context).height * .52,
      child: Align(
        alignment: Alignment.centerRight,
        child: FractionallySizedBox(
          widthFactor: 0.8,
          child: ChatReconciliationShareCard(data: payload),
        ),
      ),
    );
  }
}

class ChatReconciliationShareCard extends StatefulWidget {
  const ChatReconciliationShareCard({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  State<ChatReconciliationShareCard> createState() =>
      _ChatReconciliationShareCardState();
}

class _ChatReconciliationShareCardState
    extends State<ChatReconciliationShareCard> {
  static const _purple = Color(0xff6248d6);
  static const _confirmed = Color(0xffc8494c);
  static const _pending = Color(0xff238767);
  static const _muted = Color(0xff858994);
  int _tab = 0;
  final Set<String> _open = {};
  String get _groupLabel => '${widget.data['groupLabel'] ?? '渠道'}';
  String get _itemLabel => '${widget.data['itemLabel'] ?? '项目'}';
  String get _unitLabel => '${widget.data['unitLabel'] ?? '周期'}';

  String get _reportTitle {
    final raw = '${widget.data['date'] ?? ''}'.trim();
    final parts = raw.split('-');
    if (parts.length == 3) {
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);
      if (month != null && day != null) {
        return '${parts[0]}年$month月$day日日清月结情况汇报';
      }
    }
    return raw.isEmpty ? '日清月结情况汇报' : '$raw 日清月结情况汇报';
  }

  List<Map<String, dynamic>> get _rows =>
      (widget.data['rows'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((row) => '${row['periodCode'] ?? ''}'.toUpperCase() != 'MONTH' && '${row['period'] ?? ''}'.trim() != '本月累计')
          .toList();

  List<Map<String, dynamic>> get _people {
    final out = <String, Map<String, dynamic>>{};
    for (final row in _rows) {
      for (final raw in (row['people'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final p = Map<String, dynamic>.from(raw);
        final role = '${p['role'] ?? ''}'.trim();
        final rawNames = '${p['name'] ?? p['names'] ?? ''}';
        for (final name in rawNames.split('、')) {
          final n = name.trim();
          if (n.isEmpty || n == '未配置') continue;
          final id = '${p['id'] ?? ''}'.trim();
          final key = '${id.isEmpty ? n : id}|$role';
          final item = out.putIfAbsent(
            key,
            () => {'name': n, 'role': role, 'rows': <Map<String, dynamic>>[]},
          );
          (item['rows'] as List<Map<String, dynamic>>).add({
            'channel': row['channel'],
            'project': row['project'],
            'period': row['period'],
            'periodCode': row['periodCode'],
            'paymentTerm': row['paymentTerm'],
            'salesAmount': row['salesAmount'],
            'salesScale': row['salesScale'],
            'profitAmount': row['profitAmount'],
            'cashReceivableAmount': row['cashReceivableAmount'],
            'fundsTotal': row['fundsTotal'],
            'endingPrepayment': row['endingPrepayment'],
            'details': row['details'],
            'fundsTotal': row['fundsTotal'],
            'endingPrepayment': row['endingPrepayment'],
            'opinions': row['opinions'],
            'confirmed': p['confirmed'] == true,
          });
        }
      }
    }
    return out.values.toList();
  }

  List<Map<String, dynamic>> get _channels {
    final out = <String, Map<String, dynamic>>{};
    for (final row in _rows) {
      final name = '${row['channel'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final item = out.putIfAbsent(
        name,
        () => {'channel': name, 'rows': <Map<String, dynamic>>[]},
      );
      (item['rows'] as List<Map<String, dynamic>>).add(row);
    }
    return out.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _tab == 1 ? _channels : _people;
    final activeRows = _actionable(_rows);
    final confirmed = activeRows.where((r) => r['confirmed'] == true).length;
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: (MediaQuery.sizeOf(context).height * .55).clamp(230.0, 420.0),
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xffe5e8eb)),
          boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 12, offset: Offset(0, 3))],
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_reportTitle,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xff252333))),
                  ],
                )),
                const SizedBox(width: 8),
                SizedBox(
                  width: 62,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.done_rounded, size: 31, color: _confirmed),
                    const SizedBox(height: 2),
                    Text('$confirmed / ${activeRows.length}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _confirmed)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 5, runSpacing: 5, children: [
              _pill('${_groupLabel} ${_channels.length}', const Color(0xfff3f4f6), const Color(0xff555b66)),
              _pill('${_itemLabel} ${_projectCount(_rows)}', const Color(0xfff3f4f6), const Color(0xff555b66)),
              _pill('已确认 $confirmed', const Color(0xffffeeee), _confirmed),
              _pill('待确认 ${activeRows.length - confirmed}', const Color(0xffe7f6ef), _pending),
            ]),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var index = 0; index < 3; index++)
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _tab = index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: _tab == index
                                  ? _purple
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          ['概览', _groupLabel, '人员'][index],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: _tab == index
                                ? _purple
                                : _muted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (_tab == 0)
                      _overview(),
                    if (_tab != 0 && items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(22),
                        child: Text(_tab == 1 ? '暂无${_groupLabel}数据' : '暂无人员姓名，当前数据未提供负责人名单',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11, color: _muted)),
                      ),
                    if (_tab != 0)
                      for (var i = 0; i < items.length; i++) _item(items[i], i),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overview() {
    final groups = _channels;
    final fullyConfirmed = groups.where((group) {
      final rows = _actionable(group['rows'] as List<Map<String, dynamic>>);
      return rows.isNotEmpty && rows.every((row) => row['confirmed'] == true);
    }).length;
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(22),
        child: Text('暂无${_groupLabel}数据',
            style: const TextStyle(fontSize: 11, color: _muted)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _overviewCount('全部确认', fullyConfirmed, _confirmed, const Color(0xffffeeee))),
          const SizedBox(width: 7),
          Expanded(child: _overviewCount('仍待确认', groups.length - fullyConfirmed, _pending, const Color(0xffe7f6ef))),
        ]),
        const SizedBox(height: 11),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: const BoxDecoration(
            color: Color(0xfff4f5f7),
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(children: [
            Expanded(flex: 4, child: Text(_groupLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _muted))),
            const Expanded(flex: 3, child: Text('确认记录', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _muted))),
            const Expanded(flex: 3, child: Text('状态', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _muted))),
          ]),
        ),
        for (final group in groups) _overviewRow(group),
      ]),
    );
  }

  Widget _overviewCount(String label, int count, Color foreground, Color background) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(9)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10, color: foreground)),
          const SizedBox(height: 2),
          Text('$count 个$_groupLabel', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: foreground)),
        ]),
      );

  Widget _overviewRow(Map<String, dynamic> group) {
    final rows = _actionable(group['rows'] as List<Map<String, dynamic>>);
    final done = rows.where((row) => row['confirmed'] == true).length;
    final allDone = rows.isNotEmpty && done == rows.length;
    final status = allDone ? '已确认' : done == 0 ? '未确认' : '部分确认';
    final color = allDone ? _confirmed : _pending;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xffeff0f2)))),
      child: Row(children: [
        Expanded(
          flex: 4,
          child: Text('${group['channel'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xff343944))),
        ),
        Expanded(
          flex: 3,
          child: Text('$done / ${rows.length}', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ),
        Expanded(
          flex: 3,
          child: Text(status, textAlign: TextAlign.right,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ),
      ]),
    );
  }

  Widget _item(Map<String, dynamic> item, int index) {
    final name = _tab == 1
        ? '${item['channel'] ?? ''}'
        : '${item['name'] ?? ''}';
    final key = '$_tab-$index';
    final rows = (item['rows'] as List<Map<String, dynamic>>);
    final active = _actionable(rows);
    final confirmedCount = active.where((r) => r['confirmed'] == true).length;
    final pendingCount = active.length - confirmedCount;
    final projectCount = _projectCount(rows);
    return InkWell(
      onTap: () => setState(() {
        if (_open.contains(key)) {
          _open.remove(key);
        } else {
          _open.add(key);
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
        decoration: BoxDecoration(
          color: _open.contains(key) ? const Color(0xfffcfbff) : Colors.white,
          border: const Border(bottom: BorderSide(color: Color(0xffeff0f2))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_open.contains(key) ? Icons.keyboard_arrow_down_rounded : Icons.chevron_right_rounded,
                    size: 18, color: _muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(_tab == 1 ? name : '$name（${item['role'] ?? ''}）',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                Text('$projectCount $_itemLabel · ${active.length} $_unitLabel',
                    style: const TextStyle(fontSize: 10, color: _muted)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 5),
              child: Wrap(spacing: 5, runSpacing: 5, children: [
                _pill('已确认 $confirmedCount', const Color(0xffffeeee), _confirmed),
                _pill('待确认 $pendingCount', const Color(0xffe7f6ef), _pending),
              ]),
            ),
            if (_open.contains(key))
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 9),
                child: _projectList(rows, key),
              ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _actionable(List<Map<String, dynamic>> rows) => [
    for (final row in rows)
      if ('${row['periodCode'] ?? ''}'.toUpperCase() != 'MONTH' &&
          '${row['period'] ?? ''}'.trim() != '本月累计')
        row,
  ];

  int _projectCount(List<Map<String, dynamic>> rows) => {
    for (final row in rows)
      if ('${row['project'] ?? ''}'.trim().isNotEmpty)
        '${row['channel'] ?? ''}|${row['project'] ?? ''}',
  }.length;

  Widget _pill(String label, Color background, Color foreground) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (label.startsWith('已确认')) ...[
        const Icon(Icons.done_rounded, size: 13, color: _confirmed),
        const SizedBox(width: 3),
      ],
      Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: foreground)),
    ]),
  );

  Widget _projectList(List<Map<String, dynamic>> rows, String parentKey) {
    final projects = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final name = '${row['project'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final key = '${row['channel'] ?? ''}|$name';
      projects.putIfAbsent(key, () => []).add(row);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: const Color(0xfff7f8fb), borderRadius: BorderRadius.circular(9)),
      child: Column(children: [
        for (final entry in projects.entries) _projectRow(entry.value, '$parentKey:${entry.key}'),
      ]),
    );
  }

  Widget _projectRow(List<Map<String, dynamic>> rows, String key) {
    final active = _actionable(rows);
    final done = active.where((r) => r['confirmed'] == true).length;
    final expanded = _open.contains(key);
    final project = '${rows.first['project'] ?? ''}';
    final channel = '${rows.first['channel'] ?? ''}';
    return Column(children: [
      InkWell(
        onTap: () => setState(() => expanded ? _open.remove(key) : _open.add(key)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            Expanded(child: Text(_tab == 1 ? project : '$project · $channel',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
            const SizedBox(width: 6),
            Text('$done/${active.length} $_unitLabel',
              style: TextStyle(fontSize: 10, color: done == active.length ? _confirmed : _pending)),
            const SizedBox(width: 2),
            Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 16, color: _muted),
          ]),
        ),
      ),
      if (expanded)
        for (final row in rows) _periodRow(row),
      const Divider(height: 1, color: Color(0xffeaebee)),
    ]);
  }

  Widget _periodRow(Map<String, dynamic> row) {
    final done = row['confirmed'] == true;
    final period = '${row['period'] ?? ''}'.trim();
    final details = <String>[
      if (_groupLabel != '省份') ...[
        if ('${row['paymentTerm'] ?? ''}'.trim().isNotEmpty)
          '回款 ${row['paymentTerm']}',
        if (row['salesAmount'] is num && (row['salesAmount'] as num) != 0)
          '销售额 ${(row['salesAmount'] as num).toStringAsFixed(2)}',
        if (row['salesScale'] is num && (row['salesScale'] as num) != 0)
          '规模 ${(row['salesScale'] as num).toStringAsFixed(2)}',
      ],
    ];
    final opinions = (row['opinions'] as List? ?? const []).map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xffe8eaed)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(period.isEmpty ? '对账记录' : period,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xff343944)))),
            _pill(done ? '已确认' : '待确认',
              done ? const Color(0xffffeeee) : const Color(0xffe7f6ef),
              done ? _confirmed : _pending),
          ]),
          const SizedBox(height: 8),
          Row(children: _groupLabel == '省份'
              ? [
                  Expanded(child: _metric('资金合计', _tag2Value(row, 'fundsTotal', '资金合计'), const Color(0xfff1effb), _purple)),
                  const SizedBox(width: 6),
                  Expanded(child: _metric('期末预付款余额', _tag2Value(row, 'endingPrepayment', '期末预付款余额'), const Color(0xffeef4fb), const Color(0xff28679b))),
                ]
              : [
                  Expanded(child: _metric('利润', row['profitAmount'] ?? 0, const Color(0xfff1effb), _purple)),
                  const SizedBox(width: 6),
                  Expanded(child: _metric('现金应收', row['cashReceivableAmount'] ?? 0, const Color(0xffeef4fb), const Color(0xff28679b))),
                ]),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(details.join('  ·  '), style: const TextStyle(fontSize: 10, height: 1.5, color: _muted)),
          ],
          if (!done && opinions.isNotEmpty) ...[
            const SizedBox(height: 7),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xffe7f6ef), borderRadius: BorderRadius.circular(6)),
              child: Text('待确认意见：${opinions.first}', style: const TextStyle(fontSize: 10, height: 1.4, color: _pending)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _metric(String label, dynamic value, Color background, Color color) {
    final numeric = value is num ? value : num.tryParse('$value'.replaceAll(',', ''));
    final amount = numeric == null ? '—' : '¥${numeric.toStringAsFixed(2)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(7)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 9, color: color)),
        const SizedBox(height: 3),
        Text(amount, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }

  dynamic _tag2Value(Map<String, dynamic> row, String field, String label) {
    final value = row[field];
    if (value != null && '$value'.trim().isNotEmpty) return value;
    for (final detail in (row['details'] as List? ?? const [])) {
      final text = '$detail'.trim();
      if (text.startsWith('$label ')) return text.substring(label.length).trim();
    }
    return null;
  }

}
