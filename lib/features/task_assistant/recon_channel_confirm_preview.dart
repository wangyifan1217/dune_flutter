import '../conversation/conversation_models.dart';

/// 对账助手里给对账人看的渠道对账名片。看完改回 false。
const kReconChannelStaticPreview = true;

class ReconChannelDayLine {
  const ReconChannelDayLine({
    required this.date,
    required this.receivable,
    required this.received,
  });

  final String date;
  final num receivable;
  final num received;
}

class ReconChannelSnapshot {
  const ReconChannelSnapshot({
    required this.id,
    required this.channel,
    required this.asOfDate,
    required this.settlementCycle,
    required this.receivableAmount,
    required this.monthReceivable,
    required this.monthReceived,
    this.lines = const [],
  });

  final String id;
  final String channel;
  final String asOfDate;
  final String settlementCycle;
  final num receivableAmount;
  final num monthReceivable;
  final num monthReceived;
  final List<ReconChannelDayLine> lines;

  bool get isMonthly => settlementCycle.toUpperCase().startsWith('M+');

  String get periodLabel {
    if (!isMonthly) return asOfDate;
    final value = DateTime.tryParse(asOfDate);
    if (value == null) return asOfDate;
    return '${value.year}年${value.month}月';
  }

  factory ReconChannelSnapshot.fromJson(Map<String, dynamic> json) {
    return ReconChannelSnapshot(
      id: '${json['id'] ?? ''}',
      channel: '${json['channel'] ?? ''}',
      asOfDate: '${json['asOfDate'] ?? ''}',
      settlementCycle:
          '${json['settlementCycle'] ?? 'D+${(json['delayDays'] as num?)?.toInt() ?? 0}'}',
      receivableAmount: json['receivableAmount'] as num? ?? 0,
      monthReceivable: json['monthReceivable'] as num? ?? 0,
      monthReceived: json['monthReceived'] as num? ?? 0,
      lines: (json['lines'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (e) => ReconChannelDayLine(
              date: '${e['date'] ?? ''}',
              receivable: e['receivable'] as num? ?? 0,
              received: e['received'] as num? ?? 0,
            ),
          )
          .toList(growable: false),
    );
  }
}

String formatReconChannelMoney(num value) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final raw = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final left = raw.length - i;
    if (i > 0 && left % 3 == 0) buf.write(',');
    buf.write(raw[i]);
  }
  return '${negative ? '-' : ''}$buf.${parts[1]}';
}

List<ReconChannelSnapshot> reconChannelPreviewPack({required String asOfDate}) {
  if (asOfDate == '2026-09-10') {
    return const [
      ReconChannelSnapshot(
        id: 'hangzhou-0910',
        channel: '杭州推客',
        asOfDate: '2026-09-10',
        settlementCycle: 'D+3',
        receivableAmount: 143100,
        monthReceivable: 1151600,
        monthReceived: 1082500,
        lines: [
          ReconChannelDayLine(
            date: '2026-09-09',
            receivable: 38200,
            received: 36000,
          ),
          ReconChannelDayLine(
            date: '2026-09-08',
            receivable: 58200,
            received: 58200,
          ),
          ReconChannelDayLine(
            date: '2026-09-07',
            receivable: 46700,
            received: 46700,
          ),
        ],
      ),
    ];
  }
  return const [
    ReconChannelSnapshot(
      id: 'hangzhou-0911',
      channel: '杭州推客',
      asOfDate: '2026-09-11',
      settlementCycle: 'D+3',
      receivableAmount: 128400,
      monthReceivable: 1280000,
      monthReceived: 1196500,
      lines: [
        ReconChannelDayLine(
          date: '2026-09-10',
          receivable: 42000,
          received: 42000,
        ),
        ReconChannelDayLine(
          date: '2026-09-09',
          receivable: 38200,
          received: 36000,
        ),
        ReconChannelDayLine(
          date: '2026-09-08',
          receivable: 48200,
          received: 48200,
        ),
      ],
    ),
    ReconChannelSnapshot(
      id: 'petro-0911',
      channel: '中石油渠道',
      asOfDate: '2026-09-11',
      settlementCycle: 'D+2',
      receivableAmount: 256800,
      monthReceivable: 2480000,
      monthReceived: 2412000,
      lines: [
        ReconChannelDayLine(
          date: '2026-09-10',
          receivable: 128000,
          received: 128000,
        ),
        ReconChannelDayLine(
          date: '2026-09-09',
          receivable: 128800,
          received: 120000,
        ),
      ],
    ),
    ReconChannelSnapshot(
      id: 'energy-0911',
      channel: '月结能源渠道',
      asOfDate: '2026-09-11',
      settlementCycle: 'M+1',
      receivableAmount: 920000,
      monthReceivable: 920000,
      monthReceived: 886000,
    ),
  ];
}

List<NativeChatMessage> reconChannelPreviewMessages() {
  return [
    NativeChatMessage(
      id: -91010,
      senderUserId: 0,
      senderName: '对账助手',
      kind: 'TEXT',
      bodyText: '「2026-09-10」还有 1 张渠道对账待确认。',
      createdAt: DateTime(2026, 9, 10, 11, 0),
      payload: {
        'type': 'reconChannelConfirm',
        'asOfDate': '2026-09-10',
        'channels': reconChannelPreviewPack(asOfDate: '2026-09-10')
            .map(_channelJson)
            .toList(),
      },
    ),
    NativeChatMessage(
      id: -91011,
      senderUserId: 0,
      senderName: '对账助手',
      kind: 'TEXT',
      bodyText: '「2026-09-11」对账已生成，请核对应收实收后确认。一天可能有多张渠道名片。',
      createdAt: DateTime(2026, 9, 11, 11, 0),
      payload: {
        'type': 'reconChannelConfirm',
        'asOfDate': '2026-09-11',
        'channels': reconChannelPreviewPack(asOfDate: '2026-09-11')
            .map(_channelJson)
            .toList(),
      },
    ),
  ];
}

List<NativeChatMessage> withReconChannelPreview(
  List<NativeChatMessage> messages,
) {
  if (!kReconChannelStaticPreview) return messages;
  final preview = reconChannelPreviewMessages();
  final ids = preview.map((m) => m.id).toSet();
  return [
    ...messages.where((m) => !ids.contains(m.id)),
    ...preview,
  ];
}

Map<String, dynamic> _channelJson(ReconChannelSnapshot ch) {
  return {
    'id': ch.id,
    'channel': ch.channel,
    'asOfDate': ch.asOfDate,
    'settlementCycle': ch.settlementCycle,
    'receivableAmount': ch.receivableAmount,
    'monthReceivable': ch.monthReceivable,
    'monthReceived': ch.monthReceived,
    'lines': [
      for (final line in ch.lines)
        {
          'date': line.date,
          'receivable': line.receivable,
          'received': line.received,
        },
    ],
  };
}
