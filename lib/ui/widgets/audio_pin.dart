import 'package:flutter/material.dart';
import 'audio_bubble.dart';

class AudioPin extends StatefulWidget {
  final Offset position; // coordenadas no layer (pixels)
  final String path;
  final void Function(Offset newPosition) onDragEnd;
  final VoidCallback? onDelete;

  const AudioPin({
    super.key,
    required this.position,
    required this.path,
    required this.onDragEnd,
    this.onDelete,
  });

  @override
  State<AudioPin> createState() => _AudioPinState();
}

class _AudioPinState extends State<AudioPin> with SingleTickerProviderStateMixin {
  late Offset _pos;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _pos = widget.position;
  }

  @override
  void didUpdateWidget(covariant AudioPin oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      _pos = widget.position;
    }
  }

  @override
  Widget build(BuildContext context) {
    // largura máxima da forma expandida
    const expandedWidth = 260.0;
    const pinSize = 36.0;

    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      child: GestureDetector(
        onPanStart: (_) {
          // arrastar só quando recolhido (para não “puxar” a bubble)
          if (!_expanded) {
            // noop, apenas permitir pan
          }
        },
        onPanUpdate: (d) {
          if (_expanded) return;
          setState(() => _pos += d.delta);
        },
        onPanEnd: (_) {
          if (_expanded) return;
          widget.onDragEnd(_pos);
        },
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: _expanded ? const EdgeInsets.only(right: 10) : EdgeInsets.zero,
          decoration: _expanded
              ? BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withAlpha((0.95 * 255).round()),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha((0.25 * 255).round()),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                )
              : const BoxDecoration(),
          width: _expanded ? expandedWidth : pinSize,
          height: pinSize,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // “pino” circular
              Container(
                width: pinSize,
                height: pinSize,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha((0.25 * 255).round()),
                      blurRadius: 8,
                    )
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(
                  _expanded ? Icons.keyboard_arrow_right : Icons.multitrack_audio,
                  size: 18,
                  color: Colors.white,
                ),
              ),

              // conteúdo expandido: bubble com player
              if (_expanded) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: AudioBubble(path: widget.path),
                ),
                if (widget.onDelete != null)
                  IconButton(
                    tooltip: 'Remover',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onDelete,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
