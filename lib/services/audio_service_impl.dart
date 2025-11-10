import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:path/path.dart' as p;
import '../../main.dart';
import 'audio_service.dart';

// audio_service_impl.dart
//
// Propósito geral:
// - Implementação concreta de `AudioService` responsável por gravar áudio
//   (microfone) e reproduzir ficheiros de áudio locais. Usa `record` para
//   captura e `just_audio` para reprodução, além de `audio_session` para
//   configurar a sessão de áudio apropriada.
// - Fornece métodos para iniciar/parar gravação, tocar/parar reprodução e
//   expõe flags de estado (isRecording/isPlaying).
//
// Notas de implementação:
// - Os caminhos dos ficheiros são geridos pelo `StorageService` através do
//   `ServiceLocator` (ex.: `ServiceLocator.instance.storage.audioDir()`).
// - A gravação verifica permissões de microfone antes de começar.
// - É importante gerir o estado interno (_recording/_playing) para que a
//   UI possa refletir corretamente o estado atual.

class AudioServiceImpl implements AudioService {
  // Instância do gravador 'record' para captura do microfone.
  final AudioRecorder _record = AudioRecorder();

  // Player para reprodução de ficheiros de áudio.
  final _player = AudioPlayer();

  // Estado interno simples que indica se estamos a gravar/reproduzir.
  bool _recording = false;
  bool _playing = false;
  DateTime? _startTime;

  // Getters públicos para a UI consultar o estado.
  @override
  bool get isRecording => _recording;
  @override
  bool get isPlaying => _playing;

  // Inicia uma gravação e devolve o caminho do ficheiro onde a gravação será guardada.
  // - Configura a sessão de áudio para `speech` antes de iniciar.
  // - Verifica permissão de microfone e lança se não houver.
  @override
  Future<String> startRecording({String? suggestedFileName}) async {
    final audioDir = await ServiceLocator.instance.storage.audioDir();
    final filename = suggestedFileName ?? 'note_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final outPath = p.join(audioDir, filename);

    // Configurar sessão de áudio para captura de voz.
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());

    // Verificar permissões antes de começar.
    if (!await _record.hasPermission()) {
      throw Exception('Sem permissão de microfone');
    }

    // Iniciar gravação com configuração desejada.
    await _record.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
      ),
      path: outPath,
    );

    // Atualizar estado interno e guardar o tempo de início para calcular
    // a duração quando pararmos.
    _recording = true;
    _startTime = DateTime.now();
    return outPath;
  }

  // Para a gravação em curso e devolve a duração (ms).
  // - Se não havia gravação em curso devolve 0.
  @override
  Future<int> stopRecording() async {
    if (!_recording) return 0;
    await _record.stop();
    _recording = false;
    final dur = DateTime.now().difference(_startTime ?? DateTime.now()).inMilliseconds;
    return dur;
  }

  // Toca o ficheiro de áudio em `path`.
  // - Configura a sessão para `music`.
  // - Atualiza `_playing` e escuta o stream de estado do player para sinalizar o fim da reprodução.
  @override
  Future<void> play(String path) async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await _player.setFilePath(path);
    _playing = true;

    // Escutar o stream de estado para atualizar a flag quando termina.
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed || !s.playing) {
        _playing = false;
      }
    });
    await _player.play();
  }

  /// Para a reprodução atual imediatamente.
  @override
  Future<void> stopPlayback() async {
    await _player.stop();
    _playing = false;
  }
}
