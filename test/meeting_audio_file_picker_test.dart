import 'package:dunes_app/features/meeting/meeting_audio_file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('meeting audio drop accepts common recording extensions', () {
    expect(MeetingAudioFilePicker.isSupportedAudioName('周例会.m4a'), isTrue);
    expect(MeetingAudioFilePicker.isSupportedAudioName(r'C:\rec\a.WAV'), isTrue);
    expect(MeetingAudioFilePicker.isSupportedAudioName('clip.mp3'), isTrue);
    expect(MeetingAudioFilePicker.isSupportedAudioName('notes.pdf'), isFalse);
    expect(MeetingAudioFilePicker.isSupportedAudioName('folder'), isFalse);
  });
}
