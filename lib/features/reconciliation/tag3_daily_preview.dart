import '../conversation/conversation_models.dart';
import 'tag3_daily_models.dart';

/// 对账助手 / 工作台日清月结：关闭本地样例，只展示接口数据。
const kTag3DailyStaticPreview = false;

const int kTag3DailyPreviewMessageId = -91717;

String tag3DailyPreviewAsOfDate([DateTime? now]) {
  final value = now ?? DateTime.now();
  return _ymd(value);
}

String _ymd(DateTime value) {
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '${value.year}-$m-$d';
}

NativeChatMessage tag3DailyPreviewMessage({String? asOfDate}) {
  final date = asOfDate ?? tag3DailyPreviewAsOfDate();
  return NativeChatMessage(
    id: kTag3DailyPreviewMessageId,
    senderUserId: 0,
    senderName: '对账助手',
    kind: 'RECONCILIATION',
    bodyText: '$date 业财一体-日清月结已生成，业务/运营请各自核对并确认',
    createdAt: DateTime.now(),
    payload: {
      'type': 'reconciliation',
      'cardType': 'TAG3_DAILY',
      'asOfDate': date,
      'title': '业财一体-日清月结',
      'subtitle': '$date · 点击查看明细',
      'action': 'openTag3Daily',
      'viewerOnly': false,
    },
  );
}

List<NativeChatMessage> withTag3DailyPreview(
  List<NativeChatMessage> messages, {
  String? asOfDate,
}) {
  if (!kTag3DailyStaticPreview) return messages;
  final date = asOfDate ?? tag3DailyPreviewAsOfDate();
  final hasToday = messages.any((msg) {
    final payload = msg.payload ?? const <String, dynamic>{};
    return isTag3DailyCard('${payload['cardType'] ?? ''}') &&
        '${payload['asOfDate'] ?? ''}'.trim() == date;
  });
  if (hasToday) {
    return messages.where((m) => m.id != kTag3DailyPreviewMessageId).toList();
  }
  final preview = tag3DailyPreviewMessage(asOfDate: date);
  return [
    ...messages.where((m) => m.id != preview.id),
    preview,
  ];
}

Tag3DailySnapshot tag3DailyPreviewSnapshot({String? asOfDate}) {
  final date = asOfDate ?? tag3DailyPreviewAsOfDate();
  final asOf = DateTime.tryParse(date) ?? DateTime.now();
  final prev = asOf.subtract(const Duration(days: 1));
  final today = _ymd(asOf);
  final yesterday = _ymd(prev);
  Map<String, dynamic> day({
    required String rowKey,
    required String channel,
    required String project,
    required String period,
    required String periodLabel,
    required String statDate,
    required num sales,
    required num write,
    required num profit,
    required num rec,
    required num paid,
    required bool confirm,
    String stage = 'BUSINESS',
  }) {
    return {
      'rowKey': rowKey,
      'channelCategoryL1Name': channel,
      'projectName': project,
      'period': period,
      'periodLabel': periodLabel,
      'statDate': statDate,
      'paymentTerm': 'D+1',
      'salesAmount': sales,
      'writeOffAmount': write,
      'profitAmount': profit,
      'cashFlowAmount': 0,
      'cashReceivableAmount': rec,
      'cashPaidAmount': paid,
      'cashReceivableDiff': rec - paid,
      'subsidyReceivableAmount': 0,
      'confirmationStatus': period == 'MONTH' ? '' : 'WAIT_BUSINESS',
      'confirmationStatusLabel': period == 'MONTH' ? '' : '待业务确认',
      'canConfirm': confirm && period != 'MONTH',
      'canComment': period != 'MONTH',
      'canConfirmStage': period == 'MONTH' ? '' : stage,
    };
  }

  return Tag3DailySnapshot.fromJson({
    'asOfDate': today,
    'rows': [
      day(
        rowKey: '多渠道|亿科景信',
        channel: '多渠道',
        project: '亿科景信',
        period: 'DAY',
        periodLabel: today,
        statDate: '$today 00:00:00',
        sales: 760,
        write: 355,
        profit: 108.40,
        rec: 242.10,
        paid: 0,
        confirm: true,
      ),
      day(
        rowKey: '多渠道|亿科景信',
        channel: '多渠道',
        project: '亿科景信',
        period: 'DAY',
        periodLabel: yesterday,
        statDate: '$yesterday 00:00:00',
        sales: 720,
        write: 340,
        profit: 102.20,
        rec: 238.20,
        paid: 0,
        confirm: true,
      ),
      day(
        rowKey: '多渠道|亿科景信',
        channel: '多渠道',
        project: '亿科景信',
        period: 'MONTH',
        periodLabel: '本月累计',
        statDate: today,
        sales: 15590,
        write: 5815,
        profit: 1740.07,
        rec: 4072.70,
        paid: 102000,
        confirm: false,
      ),
      day(
        rowKey: '运营商|江苏移动',
        channel: '运营商',
        project: '江苏移动',
        period: 'DAY',
        periodLabel: today,
        statDate: '$today 00:00:00',
        sales: 210,
        write: 80,
        profit: 0,
        rec: 0,
        paid: 0,
        confirm: false,
        stage: 'OPERATION',
      ),
      day(
        rowKey: '运营商|江苏移动',
        channel: '运营商',
        project: '江苏移动',
        period: 'DAY',
        periodLabel: yesterday,
        statDate: '$yesterday 00:00:00',
        sales: 200,
        write: 70,
        profit: 0,
        rec: 0,
        paid: 0,
        confirm: false,
        stage: 'WAIT_OPERATION',
      ),
      day(
        rowKey: '运营商|江苏移动',
        channel: '运营商',
        project: '江苏移动',
        period: 'MONTH',
        periodLabel: '本月累计',
        statDate: today,
        sales: 446605,
        write: 2655,
        profit: -20,
        rec: 0,
        paid: 0,
        confirm: false,
      ),
    ],
    'assignees': [
      {
        'rowKey': '多渠道|亿科景信',
        'businessUsers': [
          {'userId': 12, 'name': '张三', 'phone': '13800001111'},
        ],
        'operationUsers': [
          {'userId': 15, 'name': '李四', 'phone': '13900002222'},
        ],
      },
      {
        'rowKey': '运营商|江苏移动',
        'businessUsers': [
          {'userId': 18, 'name': '赵六', 'phone': '13700003333'},
        ],
        'operationUsers': [
          {'userId': 19, 'name': '王五', 'phone': '13600004444'},
        ],
      },
    ],
    'comments': [
      {
        'id': 1,
        'rowKey': '多渠道|亿科景信',
        'period': 'DAY',
        'statDate': yesterday,
        'periodLabel': yesterday,
        'projectName': '亿科景信',
        'userId': 12,
        'userName': '张三',
        'kind': 'COMMENT',
        'body': '核销偏少，先记一笔',
        'createdAt': '${yesterday}T10:12:00+08:00',
      },
    ],
  });
}
