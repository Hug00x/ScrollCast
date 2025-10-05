import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/annotations.dart';

typedef AudioMoveCallback = Future<void> Function(int index, Offset newPos);
typedef AudioDeleteCallback = Future<void> Function(int index);

class AudioPinLayer extends StatefulWidget {
  const AudioPinLayer({
    super.key,
    required this.notes,
    required this.onMove,
    required this.onDelete,
    required this.scale,
    required this.overlay, // <- novo
  });

  final List<AudioNote> notes;
  final AudioMoveCallback onMove;
  final AudioDeleteCallback onDelete;
  final double scale;
  final OverlayState overlay;

  @override
  State<AudioPinLayer> createState() => _AudioPinLayerState();
}

class _AudioPinLayerState extends State<AudioPinLayer> {
  final _entries = <int, OverlayEntry>{};

  @override
  void dispose() {
    for (final e in _entries.values) {
      e.remove();
    }
    _entries.clear();
    super.dispose();
  }

  void _toggleHud(int i, Rect pinRect) {
    // fecha se já existir
    if (_entries.containsKey(i)) {
      _entries[i]!.remove();
      _entries.remove(i);
      setState(() {});
      return;
    }

    final entry = OverlayEntry(
      builder: (ctx) => _AudioHudFloating(
        anchor: pinRect,
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
        onRelayout: () => setState(() {}), // para repintar se mexer
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
                pinRect: pinRect(widget.notes[i].position),
                onTap: (rect) => _toggleHud(i, rect),
                onMove: (pos) => widget.onMove(i, pos),
              ),
          ],
        );
      },
    );
  }
}

class _AudioPin extends StatefulWidget {
  const _AudioPin({
    required this.note,
    required this.scale,
    required this.pinRect,
    required this.onTap,
    required this.onMove,
  });

  final AudioNote note;
  final double scale;
  final Rect pinRect;
  final ValueChanged<Rect> onTap;
  final ValueChanged<Offset> onMove;

  @override
  State<_AudioPin> createState() => _AudioPinState();
}

class _AudioPinState extends State<_AudioPin> {
  late Offset _pos;

  @override
  void initState() {
    super.initState();
    _pos = widget.note.position;
  }

  @override
  void didUpdateWidget(covariant _AudioPin oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.position != widget.note.position) {
      _pos = widget.note.position;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rect = widget.pinRect;
    const s = 28.0;

    return Positioned(
      left: rect.left,
      top: rect.top,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () => widget.onTap(rect),
        onPanUpdate: (d) {
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

/// HUD flutuante em Overlay (mede o próprio tamanho, sem altura fixa).
class _AudioHudFloating extends StatefulWidget {
  const _AudioHudFloating({
    required this.anchor,
    required this.onClose,
    required this.onDelete,
    required this.filePath,
    required this.durationMsHint,
    required this.onRelayout,
  });

  final Rect anchor;
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

  @override
  void initState() {
    super.initState();
    _topLeft = _suggestPos(widget.anchor);
    _init();
  }

  @override
  void didUpdateWidget(covariant _AudioHudFloating oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.anchor != widget.anchor) {
      _topLeft = _suggestPos(widget.anchor);
    }
  }

  Offset _suggestPos(Rect anchor) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final overlaySize = overlay.size;
    const hGuess = 120.0;

    // tenta acima, senão abaixo
    final above = Offset(
      (anchor.center.dx - _w / 2).clamp(8, overlaySize.width - _w - 8),
      (anchor.top - 8 - hGuess).clamp(8, overlaySize.height - hGuess - 8),
    );
    if (above.dy >= 8) return above;

    return Offset(
      (anchor.center.dx - _w / 2).clamp(8, overlaySize.width - _w - 8),
      (anchor.bottom + 8).clamp(8, overlaySize.height - hGuess - 8),
    );
  }

  Future<void> _init() async {
    try {
      await _player.setFilePath(widget.filePath);
      _dur = _player.duration ?? Duration(milliseconds: widget.durationMsHint);
    } catch (_) {
      _dur = Duration(milliseconds: widget.durationMsHint);
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    _posSub = _player.positionStream.listen((d) {
      if (mounted) setState(() => _pos = d);
    });

    _stateSub = _player.playerStateStream.listen((s) async {
      // reset no fim
      if (s.processingState == ProcessingState.completed) {
        await _player.pause();
        await _player.seek(Duration.zero);
        if (mounted) {
          setState(() {
            _playing = false;
            _pos = Duration.zero;
          });
        }
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
    return Positioned(
      left: _topLeft.dx,
      top: _topLeft.dy,
      width: _w,
      child: GestureDetector(
        onPanUpdate: (d) {
          final overlay =
              Overlay.of(context).context.findRenderObject() as RenderBox;
          final size = overlay.size;
          final nx = (_topLeft.dx + d.delta.dx).clamp(8, size.width - _w - 8);
          final ny = (_topLeft.dy + d.delta.dy).clamp(8, size.height - 60);
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
                      Row(
                        children: [
                          const Icon(Icons.mic_rounded, size: 18),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text('Áudio',
                                style: TextStyle(fontWeight: FontWeight.w600)),
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
                            icon: Icon(_playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 7),
                                    overlayShape: const RoundSliderOverlayShape(
                                        overlayRadius: 12),
                                  ),
                                  child: Slider(
                                    min: 0,
                                    max: (_dur.inMilliseconds == 0
                                            ? 1
                                            : _dur.inMilliseconds)
                                        .toDouble(),
                                    value: _pos.inMilliseconds
                                        .clamp(0, _dur.inMilliseconds)
                                        .toDouble(),
                                    onChanged: (v) async {
                                      final d =
                                          Duration(milliseconds: v.round());
                                      await _player.seek(d);
                                      setState(() => _pos = d);
                                    },
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_fmt(_pos),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                    Text(_fmt(_dur),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
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
