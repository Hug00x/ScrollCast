import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:path/path.dart' as p;

import '../../main.dart';
import 'audio_service.dart';

class AudioServiceImpl implements AudioService {
  final AudioRecorder _record = AudioRecorder();  // << aqui
  final _player = AudioPlayer();

  bool _recording = false;
  bool _playing = false;
  DateTime? _startTime;

  @override
  bool get isRecording => _recording;
  @override
  bool get isPlaying => _playing;

  @override
  Future<String> startRecording({String? suggestedFileName}) async {
    final audioDir = await ServiceLocator.instance.storage.audioDir();
    final filename = suggestedFileName ?? 'note_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final outPath = p.join(audioDir, filename);

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());

    if (!await _record.hasPermission()) {
      throw Exception('Sem permissão de microfone');
    }

    await _record.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
      ),
      path: outPath,
    );

    _recording = true;
    _startTime = DateTime.now();
    return outPath;
  }

  @override
  Future<int> stopRecording() async {
    if (!_recording) return 0;
    await _record.stop();
    _recording = false;
    final dur = DateTime.now().difference(_startTime ?? DateTime.now()).inMilliseconds;
    return dur;
  }

  @override
  Future<void> play(String path) async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await _player.setFilePath(path);
    _playing = true;
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed || !s.playing) {
        _playing = false;
      }
    });
    await _player.play();
  }

  @override
  Future<void> stopPlayback() async {
    await _player.stop();
    _playing = false;
  }
}
