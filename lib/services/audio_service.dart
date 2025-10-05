abstract class AudioService {
  Future<String> startRecording({String? suggestedFileName});
  Future<int> stopRecording();

  Future<void> play(String path);
  Future<void> stopPlayback();

  bool get isRecording;
  bool get isPlaying;
}
