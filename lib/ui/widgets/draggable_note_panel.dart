import 'package:flutter/material.dart';
import '../../../models/annotations.dart';

/// Janela flutuante e arrastável para ver/editar uma TextNote.
/// Não está acoplada à posição do pin; abre como overlay no ecrã.
class DraggableNotePanel extends StatefulWidget {
  const DraggableNotePanel({
    super.key,
    required this.note,
    required this.initialPosition,
    required this.onPositionChanged,
    required this.onTextChanged,
    required this.onClose,
    required this.onDelete,
  });

  final TextNote note;
  final Offset initialPosition;
  final ValueChanged<Offset> onPositionChanged;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onClose;
  final VoidCallback onDelete;

  @override
  State<DraggableNotePanel> createState() => _DraggableNotePanelState();
}

class _DraggableNotePanelState extends State<DraggableNotePanel> {
  late Offset _pos;

  @override
  void initState() {
    super.initState();
    _pos = widget.initialPosition;
  }

  void _onPanUpdate(DragUpdateDetails d, Size screen) {
    final next = Offset(_pos.dx + d.delta.dx, _pos.dy + d.delta.dy);
    final clamped = Offset(
      next.dx.clamp(8.0, screen.width - 8.0),
      next.dy.clamp(kToolbarHeight + 8.0, screen.height - 8.0),
    );
    setState(() => _pos = clamped);
    widget.onPositionChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) => _onPanUpdate(d, size),
        child: Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(14),
          color: scheme.surface,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Cabeçalho
                  Row(
                    children: [
                      Icon(Icons.sticky_note_2_rounded, size: 18, color: scheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Nota',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Apagar',
                        onPressed: widget.onDelete,
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Conteúdo editável
                  TextFormField(
                    initialValue: widget.note.text,
                    minLines: 3,
                    maxLines: 8,
                    onChanged: widget.onTextChanged,
                    decoration: const InputDecoration(
                      hintText: 'Escreve a tua nota…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
