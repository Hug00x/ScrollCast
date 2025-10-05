import 'package:flutter/material.dart';
import '../../../models/annotations.dart';

class TextNoteBubble extends StatefulWidget {
  const TextNoteBubble({
    super.key,
    required this.note,
    required this.canvasSize,
    required this.onChanged,
    required this.onOpen,
  });

  final TextNote note;
  final Size canvasSize;
  final ValueChanged<TextNote> onChanged;
  final VoidCallback onOpen;

  @override
  State<TextNoteBubble> createState() => _TextNoteBubbleState();
}

class _TextNoteBubbleState extends State<TextNoteBubble> {
  late Offset _pos;

  @override
  void initState() {
    super.initState();
    _pos = widget.note.position;
  }

  @override
  void didUpdateWidget(covariant TextNoteBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.position != widget.note.position) {
      _pos = widget.note.position;
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final nx = (_pos.dx + d.delta.dx).clamp(0, widget.canvasSize.width);
    final ny = (_pos.dy + d.delta.dy).clamp(0, widget.canvasSize.height);
    setState(() => _pos = Offset(nx.toDouble(), ny.toDouble()));
  }

  void _onPanEnd(DragEndDetails d) {
    widget.onChanged(TextNote(position: _pos, text: widget.note.text));
  }

  @override
  Widget build(BuildContext context) {
    const pin = 28.0;

    return Positioned(
      left: (_pos.dx - pin / 2).clamp(0, (widget.canvasSize.width - pin)),
      top: (_pos.dy - pin / 2).clamp(0, (widget.canvasSize.height - pin)),
      child: GestureDetector(
        onTap: widget.onOpen,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Container(
          width: pin,
          height: pin,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFD54F), // amarelo
                Color(0xFF66BB6A), // verde
                Color(0xFF26C6DA), // ciano
              ],
            ),
            boxShadow: [
              BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3)),
            ],
          ),
          // “três traços” pretos (coerente com o design do áudio)
          child: const Icon(Icons.notes_rounded, size: 18, color: Colors.black87),
        ),
      ),
    );
  }
}
