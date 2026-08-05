import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/drive/drive_chat_event.dart';
import 'package:dunes_app/features/drive/native_drive_models.dart';

void main() {
  test('解析可点击的文件更新事件', () {
    final event = DriveChatEvent.fromPayload({
      'driveEvent': {
        'eventKey': 'UPDATE:9:2',
        'action': 'UPDATE',
        'actorName': '张三',
        'spaceId': 1,
        'itemId': 9,
        'fileName': '预算.xlsx',
        'version': 2,
      },
    });

    expect(event, isNotNull);
    expect(event!.canOpen, isTrue);
    expect(event.displayText, '张三更新了「预算.xlsx」至 v2');
  });

  test('删除事件不可点击', () {
    final event = DriveChatEvent.fromPayload({
      'driveEvent': {
        'action': 'DELETE',
        'actorName': '李四',
        'itemId': 11,
        'fileName': '旧文档.docx',
      },
    });

    expect(event, isNotNull);
    expect(event!.deleted, isTrue);
    expect(event.canOpen, isFalse);
  });

  test('不完整 payload 回退为普通文本', () {
    expect(
      DriveChatEvent.fromPayload({
        'driveEvent': {'action': 'UPLOAD'},
      }),
      isNull,
    );
    expect(DriveChatEvent.fromPayload(null), isNull);
  });

  test('解析后端位置 breadcrumb 并分离文件', () {
    final location = DriveItemLocation.fromJson({
      'itemId': 9,
      'spaceId': 2,
      'status': 'active',
      'breadcrumb': [
        {'id': 3, 'name': '财务', 'type': 'folder'},
        {'id': 9, 'name': '预算.xlsx', 'type': 'file'},
      ],
    });

    expect(location.spaceId, 2);
    expect(location.folders.map((item) => item.id), [3]);
    expect(location.item.id, 9);
    expect(location.item.name, '预算.xlsx');
  });
}
