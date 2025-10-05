import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path/path.dart' as p;

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
  /// record ^6.x: usa AudioRecorder em vez de Record
  final AudioRecorder _rec = AudioRecorder();

  bool _recording = false;
  late Offset _startPos;
  Timer? _ticker;
  int _elapsedMs = 0;

  @override
  void dispose() {
    _ticker?.cancel();
    _rec.dispose(); // boa prática
    super.dispose();
  }

  Future<void> _start() async {
    // record ^6.x mantém hasPermission()
    if (!await _rec.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sem permissão de microfone')),
        );
      }
      return;
    }

    final dir = await widget.provideDirPath();
    final name = 'note_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final out = p.join(dir, name);

    // record ^6.x: start(RecordConfig, path: ...)
    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
      ),
      path: out,
    );

    _elapsedMs = 0;
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() => _elapsedMs += 100);
    });
    if (mounted) setState(() => _recording = true);
  }

  Future<void> _stop({required bool cancel}) async {
    // record ^6.x: stop() devolve String? path
    final path = await _rec.stop();
    _ticker?.cancel();
    final dur = _elapsedMs;
    if (mounted) setState(() => _recording = false);

    if (!cancel && path != null) {
      await widget.onSaved(path, dur);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (d) async {
        _startPos = d.globalPosition;
        await _start();
      },
      onLongPressMoveUpdate: (m) {
        final dx = m.globalPosition.dx - _startPos.dx;
        // arrastar ~100px para a esquerda cancela
        if (_recording && dx < -100) {
          _stop(cancel: true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Gravação cancelada')),
            );
          }
        }
      },
      onLongPressEnd: (_) async {
        if (_recording) await _stop(cancel: false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _recording ? Colors.redAccent : Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8)],
        ),
        child: Icon(_recording ? Icons.stop : Icons.mic, color: Colors.white),
      ),
    );
  }
}
