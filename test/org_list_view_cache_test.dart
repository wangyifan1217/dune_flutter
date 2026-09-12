import 'package:dunes_app/core/widgets/org_folder_bar.dart';
import 'package:dunes_app/features/kb/kb_list_cache.dart';
import 'package:dunes_app/features/kb/native_kb_models.dart';
import 'package:dunes_app/features/meeting/meeting_list_cache.dart';
import 'package:dunes_app/features/meeting/native_meeting_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    MeetingListCache.instance.clear();
    KbListCache.instance.clear();
  });

  test('meeting cache restores folder and search after leaving detail', () {
    const meeting = NativeMeetingSummary(
      meetingId: 11,
      title: '提案日清',
      meetingDate: '2026-09-11',
      createdAt: '2026-09-11T10:00:00',
      updatedAt: '2026-09-11T10:00:00',
      status: 'DONE',
      asrProgress: 100,
      folderId: 4,
    );
    MeetingListCache.instance.put(
      userId: 7,
      rows: const [meeting],
      page: 0,
      hasMore: false,
      totalCount: 1,
      keyword: '日清',
      folderFilter: const OrgFolderFilter.folder(4),
      folders: const [OrgFolderItem(id: 4, name: '提案相关')],
    );

    final snap = MeetingListCache.instance.peek(7);
    expect(snap, isNotNull);
    expect(snap!.keyword, '日清');
    expect(snap.folderFilter.queryValue, '4');
    expect(snap.rows.single.meetingId, 11);
    expect(snap.folders.single.name, '提案相关');
  });

  test('meeting invalidate keeps folder filter for reload', () {
    MeetingListCache.instance.put(
      userId: 7,
      rows: const [
        NativeMeetingSummary(
          meetingId: 11,
          title: '提案日清',
          meetingDate: '2026-09-11',
          createdAt: '2026-09-11T10:00:00',
          updatedAt: '2026-09-11T10:00:00',
          status: 'DONE',
          asrProgress: 100,
        ),
      ],
      page: 0,
      hasMore: false,
      folderFilter: const OrgFolderFilter.uncategorized(),
    );
    MeetingListCache.instance.invalidate();
    expect(MeetingListCache.instance.isStale, isTrue);
    final snap = MeetingListCache.instance.peek(7);
    expect(snap, isNotNull);
    expect(snap!.rows, isEmpty);
    expect(snap.folderFilter.queryValue, 'uncategorized');
  });

  test('kb cache restores folder and search', () {
    const doc = NativeKbDocument(
      id: '8',
      title: '手册',
      fileName: '手册.pdf',
      fileExtension: 'pdf',
      ingestionStatus: 'INDEXED',
      indexed: true,
      folderId: 3,
    );
    KbListCache.instance.put(
      userId: 7,
      docs: const [doc],
      page: 0,
      hasMore: false,
      total: 1,
      keyword: '手册',
      folderFilter: const OrgFolderFilter.folder(3),
      folders: const [OrgFolderItem(id: 3, name: '合同')],
    );
    final snap = KbListCache.instance.peek(7);
    expect(snap!.keyword, '手册');
    expect(snap.folderFilter.queryValue, '3');
    expect(snap.docs.single.id, '8');
  });
}
