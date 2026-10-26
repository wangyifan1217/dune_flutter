import 'dart:io';

import 'package:dunes_app/features/meeting/meeting_upload_coordinator.dart';
import 'package:dunes_app/features/meeting/meeting_upload_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('offline failures keep a local meeting draft', () {
    expect(
      meetingSaveFailureIsOffline(const SocketException('Failed host lookup')),
      isTrue,
    );
    expect(
      meetingSaveFailureIsOffline(
        http.ClientException('Connection closed while receiving data'),
      ),
      isTrue,
    );
    expect(meetingSaveFailureIsOffline(Exception('请求失败(400)')), isFalse);
    expect(meetingSaveFailureIsOffline(Exception('创建会议记录失败，请重试')), isFalse);
  });

  test('offline drafts survive the upload queue', () {
    const job = MeetingUploadJob(
      meetingId: -42,
      userId: 7,
      localFilePath: '/tmp/meeting.m4a',
      title: '没网会议',
      meetingDate: '2026-10-25',
      generate: false,
      createdAtMs: 1,
      error: '网络不可用，已保存在本机',
    );

    expect(meetingUploadJobIsPersistable(job), isTrue);
    expect(
      meetingUploadJobIsPersistable(job.copyWith(localFilePath: '  ')),
      isFalse,
    );
    expect(meetingUploadJobIsPersistable(job.copyWith(meetingId: 0)), isFalse);

    final restored = MeetingUploadJob.fromJson(job.toJson());
    expect(restored.meetingId, -42);
    expect(restored.title, '没网会议');
    expect(restored.error, '网络不可用，已保存在本机');
    expect(restored.copyWith(meetingId: 9).meetingId, 9);
  });
}
