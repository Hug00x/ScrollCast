import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/annotations.dart';

/*
  audio_pin_layer.dart

  Propósito geral:
  - Camada que desenha "pins" de áudio sobre uma página (por exemplo, num notebook).
  - Cada pin representa um `AudioNote` posicionado localmente; ao tocar num pin
    abre-se um HUD flutuante (Overlay) com controles de reprodução e ações (apagar/fechar).
  - A camada gere a criação/removal desses Overlays e delega movimento/apagar
    para callbacks fornecidos pelo pai (onMove, onDelete).

  Organização do ficheiro:
  - `AudioPinLayer` usa um `LayoutBuilder` para transformar as posições dos
    notes em rects locais e constrói um `_AudioPin` por nota.
  - `_AudioPin` é um widget stacking posicionado que lida com toques e drag para
    mover o pin. Quando tocado, converte a rect local para global e pede à
    camada para abrir o HUD (`_toggleHud`).
  - `_AudioHudFloating` é o overlay flutuante com um player (`just_audio`) que
    suporta play/pause, slider de posição e deletar. Está confinado aos
    `allowedBounds` quando fornecido.
*/


typedef AudioMoveCallback = Future<void> Function(int index, Offset newPos);
typedef AudioDeleteCallback = Future<void> Function(int index);

// Layer principal que contém vários pins de áudio.
class AudioPinLayer extends StatefulWidget {
  const AudioPinLayer({
    super.key,
    required this.notes,
    required this.onMove,
    required this.onDelete,
    required this.scale,
    required this.overlay,
    required this.allowedBounds,
  });

  // Lista de notas de áudio a renderizar (posições locais relativas à camada)
  final List<AudioNote> notes;
  // Callback para mover uma nota (index, nova posição local)
  final AudioMoveCallback onMove;
  // Callback para apagar uma nota
  final AudioDeleteCallback onDelete;
  // Escala atual do layer (usado para ajustar deltas de arraste)
  final double scale;
  // Overlay onde os HUDs flutuantes serão inseridos
  final OverlayState overlay;

  /// Área globalonde a HUD pode existir (a "caixa do papel").
  /// Se null, usa todo o overlay como área disponível.
  final Rect? allowedBounds;

  @override
  State<AudioPinLayer> createState() => _AudioPinLayerState();
}

class _AudioPinLayerState extends State<AudioPinLayer> {
  // Mapa de overlay entries activos por índice de nota
  final _entries = <int, OverlayEntry>{};

  @override
  void dispose() {
    // Remover todos os overlays ao destruir a camada
    for (final e in _entries.values) {
      e.remove();
    }
    _entries.clear();
    super.dispose();
  }

  // Alterna o HUD (mostra/fecha) para a nota 'i'. Recebe o rect do pin em
  // coordenadas globais para posicionar o overlay corretamente.
  void _toggleHud(int i, Rect pinRectGlobal) {
    if (_entries.containsKey(i)) {
      _entries[i]!.remove();
      _entries.remove(i);
      setState(() {});
      return;
    }

    final entry = OverlayEntry(
      builder: (ctx) => _AudioHudFloating(
        anchorGlobal: pinRectGlobal,
        allowedBounds: widget.allowedBounds,
        onClose: () {
          _entries[i]?.remove();
          _entries.remove(i);
          setState(() {});
        },
        onDelete: () async {
          await widget.onDelete(i);
          _entries[i]?.remove();
          _entries.remove(i);
          setState(() {});
        },
        filePath: widget.notes[i].filePath,
        durationMsHint: widget.notes[i].durationMs,
        onRelayout: () => setState(() {}),
      ),
    );

    widget.overlay.insert(entry);
    _entries[i] = entry;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        // Constrói um rect local centrado na posição fornecida pela nota
        Rect pinRect(Offset p) {
          const double s = 32;
          final left = (p.dx - s / 2).clamp(0, size.width - s);
          final top = (p.dy - s / 2).clamp(0, size.height - s);
          return Rect.fromLTWH(left.toDouble(), top.toDouble(), s, s);
        }

        return Stack(
          children: [
            for (int i = 0; i < widget.notes.length; i++)
              _AudioPin(
                note: widget.notes[i],
                scale: widget.scale,
                localPinRect: pinRect(widget.notes[i].position),
                // passa rect global para que o overlay saiba onde ancorar-se
                onTapGlobalRect: (globalRect) => _toggleHud(i, globalRect),
                onMove: (pos) => widget.onMove(i, pos),
              ),
          ],
        );
      },
    );
  }
}

// Widget individual que representa um pin de áudio posicionado.
class _AudioPin extends StatefulWidget {
  const _AudioPin({
    required this.note,
    required this.scale,
    required this.localPinRect,
    required this.onTapGlobalRect,
    required this.onMove,
  });

  final AudioNote note;
  final double scale;
  // Rect relativo a este layer que envolve o pin (usado para posicionar/ancorar)
  final Rect localPinRect;
  // Ao tocar, o pin converte o rect local para coordenadas globais e chama isto
  final ValueChanged<Rect> onTapGlobalRect;
  final ValueChanged<Offset> onMove;

  @override
  State<_AudioPin> createState() => _AudioPinState();
}

class _AudioPinState extends State<_AudioPin> {
  late Offset _pos;

  @override
  void initState() {
    super.initState();
    _pos = widget.note.position; // posição inicial baseada no modelo
  }

  @override
  void didUpdateWidget(covariant _AudioPin oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sincronizar posição local se o modelo mudou externamente
    if (oldWidget.note.position != widget.note.position) {
      _pos = widget.note.position;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rect = widget.localPinRect;
    const s = 28.0;

    return Positioned(
      left: rect.left,
      top: rect.top,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () {
          // converte rect local -> global para que o HUD se possa ancorar corretamente
          final rb = context.findRenderObject() as RenderBox?;
          if (rb != null) {
            final origin = rb.localToGlobal(Offset.zero);
            widget.onTapGlobalRect(rect.shift(origin));
          }
        },
        onPanUpdate: (d) {
          // ajustar delta pelo scale do layer para movimentos consistentes
          final delta = d.delta / widget.scale;
          _pos = Offset(_pos.dx + delta.dx, _pos.dy + delta.dy);
          widget.onMove(_pos);
        },
        child: Container(
          width: s,
          height: s,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFD54F),
                Color(0xFF66BB6A),
                Color(0xFF26C6DA),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.mic_rounded, size: 18, color: Colors.black87),
        ),
      ),
    );
  }
}

/// HUD flutuante em Overlay.
/// Responsável por mostrar controlos do ficheiro de áudio.
class _AudioHudFloating extends StatefulWidget {
  const _AudioHudFloating({
    required this.anchorGlobal,
    required this.allowedBounds,
    required this.onClose,
    required this.onDelete,
    required this.filePath,
    required this.durationMsHint,
    required this.onRelayout,
  });

  // Rect global do pin que ancorará o HUD
  final Rect anchorGlobal;
  // Limites globais onde a HUD pode existir; se null usa todo o overlay
  final Rect? allowedBounds;
  final VoidCallback onClose;
  final Future<void> Function() onDelete;
  final String filePath;
  final int durationMsHint;
  final VoidCallback onRelayout;

  @override
  State<_AudioHudFloating> createState() => _AudioHudFloatingState();
}

class _AudioHudFloatingState extends State<_AudioHudFloating> {
  final _player = AudioPlayer();
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;

  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _playing = false;
  bool _loading = true;

  late Offset _topLeft; // posição do card no overlay
  static const double _w = 270;
  static const double _hGuess = 120;

  @override
  void initState() {
    super.initState();
    // Sugerir posição inicial baseada no anchor e nos bounds
    _topLeft = _suggestPos(widget.anchorGlobal);
    _init();
  }

  @override
  void didUpdateWidget(covariant _AudioHudFloating oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recalcular posição se o anchor ou os limites mudarem
    if (oldWidget.anchorGlobal != widget.anchorGlobal ||
        oldWidget.allowedBounds != widget.allowedBounds) {
      _topLeft = _suggestPos(widget.anchorGlobal);
    }
  }

  // Sugere uma posição para o HUD: tenta acima do pin, caso não caiba tenta abaixo.
  Offset _suggestPos(Rect anchorGlobal) {
    // limites: se não houver bounds, usa overlay inteiro
    final overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox;
    final overlaySize = overlayBox.size;
    final Rect bounds = widget.allowedBounds ??
        Rect.fromLTWH(0, 0, overlaySize.width, overlaySize.height);

    // tenta acima do pin; se não couber, abaixo
    final tryAbove = Offset(
      (anchorGlobal.center.dx - _w / 2).clamp(bounds.left + 8, bounds.right - _w - 8),
      (anchorGlobal.top - 8 - _hGuess).clamp(bounds.top + 8, bounds.bottom - _hGuess - 8),
    );
    if (tryAbove.dy >= bounds.top + 8) return tryAbove;

    return Offset(
      (anchorGlobal.center.dx - _w / 2).clamp(bounds.left + 8, bounds.right - _w - 8),
      (anchorGlobal.bottom + 8).clamp(bounds.top + 8, bounds.bottom - _hGuess - 8),
    );
  }

  // Inicializa o player e subscreve streams de posição/estado
  Future<void> _init() async {
    try {
      await _player.setFilePath(widget.filePath);
      _dur = _player.duration ?? Duration(milliseconds: widget.durationMsHint);
    } catch (_) {
      // fallback para a duração de hint fornecida
      _dur = Duration(milliseconds: widget.durationMsHint);
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    _posSub = _player.positionStream.listen((d) {
      if (mounted) setState(() => _pos = d);
    });

    _stateSub = _player.playerStateStream.listen((s) async {
      if (s.processingState == ProcessingState.completed) {
        await _player.pause();
        await _player.seek(Duration.zero);
        if (mounted) setState(() { _playing = false; _pos = Duration.zero; });
      } else {
        if (mounted) setState(() => _playing = s.playing);
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    String t(int n) => n.toString().padLeft(2, '0');
    return '${t(d.inMinutes.remainder(60))}:${t(d.inSeconds.remainder(60))}';
  }

  @override
  Widget build(BuildContext context) {
    // Calcula bounds efetivos com base no overlay e allowedBounds
    final overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox;
    final overlaySize = overlayBox.size;
    final Rect bounds = widget.allowedBounds ??
        Rect.fromLTWH(0, 0, overlaySize.width, overlaySize.height);

    return Positioned(
      left: _topLeft.dx,
      top: _topLeft.dy,
      width: _w,
      child: GestureDetector(
        // Permite arrastar o HUD dentro dos limites calculados
        onPanUpdate: (d) {
          final nx = (_topLeft.dx + d.delta.dx)
              .clamp(bounds.left + 8, bounds.right - _w - 8);
          final ny = (_topLeft.dy + d.delta.dy)
              .clamp(bounds.top + 8, bounds.bottom - _hGuess - 8);
          setState(() => _topLeft = Offset(nx.toDouble(), ny.toDouble()));
          widget.onRelayout();
        },
        child: Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(20),
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: _loading
                ? const SizedBox(
                    height: 64,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Cabeçalho do HUD: ícone, título e ações (apagar/fechar)
                      Row(
                        children: [
                          const Icon(Icons.mic_rounded, size: 18),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text('Áudio', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Apagar',
                            onPressed: () async {
                              await _player.stop();
                              await widget.onDelete();
                            },
                            icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Fechar',
                            onPressed: widget.onClose,
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
                      // Controlos de reprodução: play/pause e slider de posição
                      Row(
                        children: [
                          IconButton.filled(
                            visualDensity: VisualDensity.compact,
                            onPressed: () async {
                              if (_playing) {
                                await _player.pause();
                              } else {
                                await _player.play();
                              }
                            },
                            icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                  ),
                                  child: Slider(
                                    min: 0,
                                    max: (_dur.inMilliseconds == 0 ? 1 : _dur.inMilliseconds).toDouble(),
                                    value: _pos.inMilliseconds.clamp(0, _dur.inMilliseconds).toDouble(),
                                    onChanged: (v) async {
                                      final d = Duration(milliseconds: v.round());
                                      await _player.seek(d);
                                      setState(() => _pos = d);
                                    },
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_fmt(_pos), style: Theme.of(context).textTheme.bodySmall),
                                    Text(_fmt(_dur), style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
