import 'package:dunes_app/features/chat/im_cached_file_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uniqueChatFileName adds (1) (2) before extension', () {
    final existing = {'预算.xlsx', '预算(1).xlsx'};
    expect(uniqueChatFileName('预算.xlsx', existing.contains), '预算(2).xlsx');
    expect(uniqueChatFileName('readme', existing.contains), 'readme');
  });

  test('allocateCachedChatFileName reuses mapping for same cacheKey', () {
    final index = {'key-a': '预算(1).xlsx'};
    final name = allocateCachedChatFileName(
      fileName: '预算.xlsx',
      cacheKey: 'key-a',
      index: index,
      exists: (n) => n == '预算.xlsx' || n == '预算(1).xlsx',
    );
    expect(name, '预算(1).xlsx');
  });

  test('allocateCachedChatFileName does not steal another message file', () {
    final index = {'key-old': '预算.xlsx'};
    final name = allocateCachedChatFileName(
      fileName: '预算.xlsx',
      cacheKey: 'key-new',
      index: index,
      exists: (n) => n == '预算.xlsx',
    );
    expect(name, '预算(1).xlsx');
  });

  test('savedChatFileRenamed detects (1) copy', () {
    expect(
      savedChatFileRenamed('预算.xlsx', r'D:\沙丘文件\12\预算(1).xlsx'),
      isTrue,
    );
    expect(
      savedChatFileRenamed('预算.xlsx', r'D:\沙丘文件\12\预算.xlsx'),
      isFalse,
    );
  });
}
