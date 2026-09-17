import 'package:dunes_app/features/conversation/im_user_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalize 空值和非法 key 回落到在线', () {
    expect(ImUserStatusCatalog.normalize(null), ImUserStatusCatalog.online);
    expect(ImUserStatusCatalog.normalize(''), ImUserStatusCatalog.online);
    expect(ImUserStatusCatalog.normalize('  '), ImUserStatusCatalog.online);
    expect(ImUserStatusCatalog.normalize('zzz'), ImUserStatusCatalog.online);
    expect(ImUserStatusCatalog.normalize('TRIP'), ImUserStatusCatalog.trip);
    expect(ImUserStatusCatalog.normalize('custom'), ImUserStatusCatalog.custom);
  });

  test('预设文案与徽章展示规则', () {
    expect(ImUserStatusCatalog.of('trip').label, '出差中');
    expect(ImUserStatusCatalog.of('rest').label, '休息中');
    expect(ImUserStatusCatalog.of('meeting').label, '会议中');
    expect(ImUserStatusCatalog.of('busy').label, '忙碌');
    expect(ImUserStatusCatalog.of('dnd').label, '勿扰');
    expect(ImUserStatusCatalog.of('leave').label, '请假中');
    expect(ImUserStatusCatalog.showsBadge('online'), isFalse);
    expect(ImUserStatusCatalog.showsBadge(''), isFalse);
    expect(ImUserStatusCatalog.showsBadge('trip'), isTrue);
    expect(ImUserStatusCatalog.showsBadge('custom'), isTrue);
    expect(
      ImUserStatusCatalog.all.map((e) => e.key),
      isNot(contains(ImUserStatusCatalog.online)),
    );
  });

  test('自定义状态最多 8 个字，并解析图标', () {
    expect(ImUserStatusCatalog.clampText('加班中'), '加班中');
    expect(ImUserStatusCatalog.clampText('客户现场勿扰中了吧'), '客户现场勿扰中了');
    expect(ImUserStatusCatalog.clampText('  出差  '), '出差');
    expect(ImUserStatusCatalog.normalizeIcon('laptop'), 'laptop');
    expect(ImUserStatusCatalog.normalizeIcon('nope'), '');

    final custom = ImUserStatusCatalog.parse(
      status: 'custom',
      text: '加班中',
      icon: 'laptop',
      color: '#7B5CD8',
    );
    expect(custom.key, ImUserStatusCatalog.custom);
    expect(custom.text, '加班中');
    expect(custom.icon, 'laptop');
    expect(custom.color, '#7b5cd8');
    expect(custom.def.label, '加班中');
    expect(custom.def.color, const Color(0xFF7B5CD8));
    expect(custom.showsBadge, isTrue);
    expect(ImUserStatusCatalog.normalizeColor('7B5'), '#77bb55');
    expect(ImUserStatusCatalog.normalizeColor('not-a-color'), '');

    expect(
      ImUserStatusCatalog.parse(status: 'custom', text: '', icon: 'laptop'),
      ImUserStatusValue.online,
    );
    expect(
      ImUserStatusCatalog.parse(status: 'custom', text: '加班中', icon: ''),
      ImUserStatusValue.online,
    );
  });
}
