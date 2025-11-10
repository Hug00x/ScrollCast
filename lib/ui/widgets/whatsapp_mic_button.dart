/*
  whatsapp_mic_button.dart

  Propósito geral:
  - Implementa um botão de gravação estilo WhatsApp: pressionar longo para
    gravar e soltar para guardar.
  - O widget trata permissões, gravação com a API `record`, e notifica o pai quando o ficheiro de áudio é guardado.

  Comportamento UX:
  - Long press start: inicia gravação.
  - Long press end: termina a gravação e chama `onSaved`.
*/

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path/path.dart' as p;

// Tipo para notificar o pai quando um ficheiro de áudio é salvo.
typedef OnAudioSaved = Future<void> Function(String filePath, int durationMs);

class WhatsAppMicButton extends StatefulWidget {
  final OnAudioSaved onSaved;
  final Future<String> Function() provideDirPath; // devolve diretório para gravar

  const WhatsAppMicButton({
    super.key,
    required this.onSaved,
    required this.provideDirPath,
  });

  @override
  State<WhatsAppMicButton> createState() => _WhatsAppMicButtonState();
}

class _WhatsAppMicButtonState extends State<WhatsAppMicButton> {
  // Usamos AudioRecorderç. Mantenho um wrapper leve aqui.
  final AudioRecorder _rec = AudioRecorder();

  // Estado visual/local
  bool _recording = false; // indicador de gravação ativo
  Timer? _ticker;
  int _elapsedMs = 0;

  @override
  void dispose() {
    // Cancelar timers e soltar recursos do recorder
    _ticker?.cancel();
    _rec.dispose(); 
    super.dispose();
  }

  // Inicia a gravação: pede permissão, obtém o diretório para guardar e
  // inicia o recorder com configuração adequada.
  Future<void> _start() async {
    // Verificar permissões de microfone
    if (!await _rec.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sem permissão de microfone')),
        );
      }
      return;
    }

    // Obter diretório para guardar e compor um nome único para o ficheiro
    final dir = await widget.provideDirPath();
    final name = 'note_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final out = p.join(dir, name);

    // Iniciar gravação com configuração razoável
    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
      ),
      path: out,
    );

    // Reiniciar contadores e iniciar ticker que atualiza `_elapsedMs` para
    // poder mostrar duração. Usamos mounted checks antes de setState.
    _elapsedMs = 0;
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() => _elapsedMs += 100);
    });
    if (mounted) setState(() => _recording = true);
  }

  // Pára a gravação e notifica o pai com o ficheiro resultante (se houver).
  // Removemos a lógica de cancelamento via drag: onLongPressEnd sempre termina
  // a gravação e guarda o ficheiro quando presente.
  Future<void> _stop() async {
    final path = await _rec.stop(); // stop devolve String? path na v6.x
    _ticker?.cancel();
    final dur = _elapsedMs;
    if (mounted) setState(() => _recording = false);

    if (path != null) {
      await widget.onSaved(path, dur);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Gesture model:
    // - onLongPressStart: regista a posição inicial e inicia gravação (_start)
    // - onLongPressEnd: termina a gravação
    return GestureDetector(
      onLongPressStart: (d) async {
        await _start();
      },
      onLongPressEnd: (_) async {
        if (_recording) await _stop();
      },
      // Visual: botão circular com transição animada entre ícone de mic e stop
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _recording ? Colors.redAccent : Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withAlpha((0.25 * 255).round()), blurRadius: 8)],
        ),
        child: Icon(_recording ? Icons.stop : Icons.mic, color: Colors.white),
      ),
    );
  }
}
