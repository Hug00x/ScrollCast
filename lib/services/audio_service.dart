//Interface abstrata para serviço de áudio
abstract class AudioService {

  //Inicia a gravação do áudio, retornando o caminho do ficheiro gravado
  Future<String> startRecording({String? suggestedFileName});
  
  //Termina a gravação do áudio
  Future<int> stopRecording();

  //Reproduz um ficheiro de áudio
  Future<void> play(String path);

  //Termina a reprodução do áudio
  Future<void> stopPlayback();

  bool get isRecording;
  bool get isPlaying;
}
