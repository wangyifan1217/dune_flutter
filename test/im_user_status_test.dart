import 'package:dunes_app/features/conversation/im_user_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalize 空值和非法 key 回落到在线', () {
    expect(ImUserStatusCatalog.normalize(null), ImUserStatusCatalog.online);
    expect(ImUserStatusCatalog.normalize(''), ImUserStatusCatalog.online);
    expect(ImUserStatusCatalog.normalize('  '), ImUserStatusCatalog.online);
    expect(ImUserStatusCatalog.normalize('zzz'), ImUserStatusCatalog.online);
    expect(ImUserStatusCatalog.normalize('TRIP'), ImUserStatusCatalog.trip);
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
    expect(
      ImUserStatusCatalog.all.map((e) => e.key),
      isNot(contains(ImUserStatusCatalog.online)),
    );
  });
}
