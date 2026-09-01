import 'package:dunes_app/features/meeting/meeting_storage_multipart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('multipart is used only when file is larger than part size', () {
    expect(MeetingStorageMultipart.shouldUse(5 * 1024 * 1024), isFalse);
    expect(MeetingStorageMultipart.shouldUse(5 * 1024 * 1024 + 1), isTrue);
  });

  test('part plan keeps 5MB slices and a remainder last part', () {
    const partSize = 5 * 1024 * 1024;
    final parts = MeetingStorageMultipart.planParts(
      partSize * 2 + 123,
      partSize: partSize,
    );
    expect(parts, hasLength(3));
    expect(parts[0].partNumber, 1);
    expect(parts[0].offset, 0);
    expect(parts[0].length, partSize);
    expect(parts[1].partNumber, 2);
    expect(parts[1].offset, partSize);
    expect(parts[1].length, partSize);
    expect(parts[2].partNumber, 3);
    expect(parts[2].offset, partSize * 2);
    expect(parts[2].length, 123);
  });

  test('etag header is normalized without quotes', () {
    expect(
      MeetingStorageMultipart.etagFromHeaders({'ETag': '"abc123"'}),
      'abc123',
    );
    expect(MeetingStorageMultipart.normalizeEtag(' "xyz" '), 'xyz');
  });

  test('ftp storage is treated as multipart unsupported', () {
    expect(
      MeetingStorageMultipart.isUnsupported(
        Exception('upload failed: 400 meeting-audio does not support multipart upload in ftp mode'),
      ),
      isTrue,
    );
  });
}
