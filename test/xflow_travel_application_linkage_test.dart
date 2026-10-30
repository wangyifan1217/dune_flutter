import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/xflow/xflow_linkage.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';

void main() {
  final span = {
    'from': 'startDate',
    'to': 'endDate',
    'suffix': '天',
  };
  final fields = [
    XflowField.fromJson({
      'key': 'travelDays',
      'type': 'computed',
      'hook': 'inclusiveDays',
      'meta': span,
    }),
    XflowField.fromJson({
      'key': 'hotelDays',
      'type': 'computed',
      'hook': 'hotelNights',
      'meta': span,
    }),
    XflowField.fromJson({
      'key': 'hotelStandard',
      'type': 'computed',
      'hook': 'hotelStandard',
    }),
    XflowField.fromJson({
      'key': 'title',
      'type': 'computed',
      'hook': 'travelTitle',
    }),
    XflowField.fromJson({
      'key': 'bookingChannel',
      'type': 'computed',
      'hook': 'bookingChannel',
    }),
  ];

  test('差旅申请按起止日期、同行人和预订方式回写只读字段', () {
    final values = <String, dynamic>{
      'visitUnit': '上海客户',
      'travelReason': '驻场对接上海客户项目上线实施，完成系统部署、核心团队操作培训以及现场支持',
      'companions': '李四(项目经理)',
      'needHotel': '是',
      'startDate': '2026-11-05 09:00',
      'endDate': '2026-11-12 18:00',
      'itineraryItems': [
        {'bookingMethod': '公司商旅平台'},
        {'bookingMethod': '公司商旅平台'},
      ],
      'bookingChannel': '自行预订',
    };
    XflowLinkage.recompute(fields, const {}, values);
    expect(values['travelDays'], '8天');
    expect(values['hotelDays'], '7天');
    expect(values['hotelStandard'], '同性别拼房标准：300元/人/晚');
    expect(
      values['title'],
      '上海客户 - 驻场对接上海客户项目上线实施，完成系统部署、核心团队操作培训...',
    );
    expect(values['bookingChannel'], '携程');
  });

  test('结束早于开始、不住宿或夹杂自行预订时清空或改写派生值', () {
    final values = <String, dynamic>{
      'needHotel': '否',
      'startDate': '2026-11-12',
      'endDate': '2026-11-05',
      'itineraryItems': [
        {'bookingMethod': '公司商旅平台'},
        {'bookingMethod': '自行预订'},
      ],
      'hotelDays': '7天',
      'hotelStandard': '同性别拼房标准：300元/人/晚',
    };
    XflowLinkage.recompute(fields, const {}, values);
    expect(values.containsKey('travelDays'), isFalse);
    expect(values.containsKey('hotelDays'), isFalse);
    expect(values.containsKey('hotelStandard'), isFalse);
    expect(values['bookingChannel'], '自行预订');
  });
}
