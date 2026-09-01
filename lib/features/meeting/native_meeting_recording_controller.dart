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

  Future<void> start({String title = ''}) async {
    await NativeAudioRecorder.instance.start(
      title: title,
      persistSession: true,
    );
    state.value = MeetingRecordingState.recordingForeground;
  }

  Future<void> pause() async {
    if (state.value == MeetingRecordingState.idle ||
        state.value == MeetingRecordingState.stopping) {
      return;
    }
    await NativeAudioRecorder.instance.pause();
  }

  Future<bool> resume() async {
    if (state.value == MeetingRecordingState.idle ||
        state.value == MeetingRecordingState.stopping) {
      return false;
    }
    final ok = await NativeAudioRecorder.instance.resume();
    if (ok) {
      state.value = MeetingRecordingState.recordingForeground;
    }
    return ok;
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
