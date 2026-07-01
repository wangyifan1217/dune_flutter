import 'package:flutter/widgets.dart';

import '../chat/native_audio_recorder.dart';

enum MeetingRecordingState {
  idle,
  recordingForeground,
  recordingBackground,
  stopping,
}

class MeetingRecordingController with WidgetsBindingObserver {
  MeetingRecordingController._();

  static final MeetingRecordingController instance =
      MeetingRecordingController._();

  final ValueNotifier<MeetingRecordingState> state =
      ValueNotifier<MeetingRecordingState>(MeetingRecordingState.idle);

  bool _attached = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  Future<void> start() async {
    await NativeAudioRecorder.instance.start();
    state.value = MeetingRecordingState.recordingForeground;
  }

  Future<NativeRecordedAudio?> stop() async {
    state.value = MeetingRecordingState.stopping;
    final audio = await NativeAudioRecorder.instance.stop();
    state.value = MeetingRecordingState.idle;
    return audio;
  }

  Future<void> cancel() async {
    await NativeAudioRecorder.instance.cancel();
    state.value = MeetingRecordingState.idle;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final current = this.state.value;
    if (current != MeetingRecordingState.recordingForeground &&
        current != MeetingRecordingState.recordingBackground) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      this.state.value = MeetingRecordingState.recordingBackground;
      return;
    }
    if (state == AppLifecycleState.resumed) {
      this.state.value = MeetingRecordingState.recordingForeground;
    }
  }
}
