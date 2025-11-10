import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../models/annotations.dart';

/*
  text_note_bubble.dart

  Propósito geral:
  - Pequeno widget circular que representa uma nota de texto (TextNote) colocada
    sobre um canvas. Serve como um 'pin' visual que o utilizador pode arrastar
    para reposicionar a nota e tocar para abrir/editar o conteúdo.
  - O widget é intencionalmente compacto: ocupa uma área circular (pin) e
    delega a edição/visualização do texto ao callback `onOpen`.

  Organização de ficheiro:
  - Recebe a posição inicial via `TextNote.position` e garante que a posição
    se mantenha dentro dos limites do `canvasSize`.
  - `onChanged` é chamado quando o usuário termina um arraste (persistir nova posição).
  - `onOpen` é chamado quando o utilizador toca na bolha (abrir editor/visualizador).
*/

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
  // Estado local: posição centro do pin no canvas.
  // Mantemos um estado local para permitir manipulação imediata durante o drag
  // e só avisamos o pai no `_onPanEnd` para persistência.
  late Offset _pos;

  @override
  void initState() {
    super.initState();
    // Inicializar posição a partir do modelo recebido
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
    // Atualiza a posição do centro durante o arrasto.
    // O clamp garante que nunca posicionamos o pin fora dos limites do canvas.
    final nx = (_pos.dx + d.delta.dx).clamp(0, widget.canvasSize.width);
    final ny = (_pos.dy + d.delta.dy).clamp(0, widget.canvasSize.height);
    setState(() => _pos = Offset(nx.toDouble(), ny.toDouble()));
  }

  void _onPanEnd(DragEndDetails d) {
    // Ao terminar o arrasto, informamos o pai para atualizar/persistir a nota
    // com a nova posição. Recriamos um novo TextNote com o texto actual.
    widget.onChanged(TextNote(position: _pos, text: widget.note.text));
  }

  @override
  Widget build(BuildContext context) {
    // Dimensão visual do pin.
    const pin = 28.0;

    // Garantir limites válidos: o upper bound do clamp nunca pode ser < 0.
    // Usamos math.max para evitar valores negativos quando o canvas for muito pequeno.
    final maxLeft = math.max(0.0, widget.canvasSize.width - pin);
    final maxTop = math.max(0.0, widget.canvasSize.height - pin);

    // Explicação do layout retornado:
    // - Usamos `Positioned` para posicionar o pin de forma absoluta dentro do
    //   canvas. Os cálculos subtraem `pin/2` porque `_pos` representa o centro.
    // - `GestureDetector` envolve o pin para captar toques (onTap -> onOpen)
    //   e arrastos (onPanUpdate/onPanEnd) para mover a nota.
    // - O Container aplica um gradiente e uma sombra para combinar com o
    //   estilo de outros pins na app; o ícone interno representa uma nota.
    return Positioned(
      left: (_pos.dx - pin / 2).clamp(0, maxLeft),
      top: (_pos.dy - pin / 2).clamp(0, maxTop),
      child: GestureDetector(
        // Tocar abre o editor/visualizador da nota
        onTap: widget.onOpen,
        // Drag para mover a nota
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
          // Ícone representando uma nota de texto — mantém coerência visual
          // com outros tipos de pins.
          child: const Icon(Icons.notes_rounded, size: 18, color: Colors.black87),
        ),
      ),
    );
  }
}
