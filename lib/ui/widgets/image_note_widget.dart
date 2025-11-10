import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/annotations.dart';

/*
  image_note_widget.dart

  Propósito geral:
  - Widget que exibe uma imagem (ImageNote) sobre o ecrã com suporte a:
    - mover (drag),
    - redimensionar uniformemente através de handles nos cantos (corner-drag),
    - rodar livremente através de um handle de rotação.
  - Quando está selecionado, mostra controlos de UI (borda, handles e botão
    de apagar) que acompanham a rotação e o scale da imagem.

  Organização do ficheiro:
  - Estado: posição centro, dimensões, rotação e flags de seleção.
  - Gestos: handlers para arrastar a imagem, para iniciar/atualizar/terminar
    redimensionamento por corner-drag e para a rotação.
  - Build: constrói uma árvore posicionada com a imagem rotacionada, uma
    camada de seleção que acompanha a rotação e handles interativos.
*/

class ImageNoteWidget extends StatefulWidget {
  const ImageNoteWidget({
    super.key,
    required this.note,
    required this.canvasSize,
    required this.onChanged,
    this.onDelete,
  });

  final ImageNote note;
  final Size canvasSize;
  final ValueChanged<ImageNote> onChanged;
  final VoidCallback? onDelete;

  @override
  State<ImageNoteWidget> createState() => _ImageNoteWidgetState();
}

class _ImageNoteWidgetState extends State<ImageNoteWidget> {
  // Estado principal do widget:
  // - _pos: centro da imagem no canvas (coordenadas locais do canvas)
  // - _w/_h: largura e altura atuais (podem mudar durante corner-drag)
  // - _rotation: ângulo em radians
  // - _selected: se o widget está selecionado (controlos visíveis)
  late Offset _pos; // center
  late double _w;
  late double _h;
  double _rotation = 0.0;
  bool _selected = false;

  // Variáveis usadas durante as interações (gestures):
  // - _startW/_startH/_startRotation: snapshot do estado quando a gesture começa
  // - _handleStartDist: distância inicial do handle ao centro para cálculo de scale
  // - _centerGlobal: centro global do widget (usado para cálculos de rotação/scale)
  late double _startW;
  late double _startH;
  late double _startRotation;
  late double _handleStartDist;
  late Offset _centerGlobal;

  // Constantes/tamanhos de UI
  static const double _minSize = 24.0;
  static const double _handleTouchSize = 56.0;
  static const double _handleVisualSize = 16.0;
  static const double _rotateHandleDistance = 30.0;

  @override
  void initState() {
    super.initState();
    // Inicializar o estado a partir do modelo recebido.
    _pos = widget.note.position;
    _w = widget.note.width;
    _h = widget.note.height;
    _rotation = widget.note.rotation;
  }

  @override
  void didUpdateWidget(covariant ImageNoteWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.position != widget.note.position) _pos = widget.note.position;
    if (oldWidget.note.width != widget.note.width) _w = widget.note.width;
    if (oldWidget.note.height != widget.note.height) _h = widget.note.height;
    if (oldWidget.note.rotation != widget.note.rotation) _rotation = widget.note.rotation;
  }


  void _onDragUpdate(DragUpdateDetails details) {
    // Atualiza a posição centro respeitando os limites do canvas
    final nx = (_pos.dx + details.delta.dx).clamp(0, widget.canvasSize.width);
    final ny = (_pos.dy + details.delta.dy).clamp(0, widget.canvasSize.height);
    setState(() => _pos = Offset(nx.toDouble(), ny.toDouble()));
  }

  void _onDragEnd(DragEndDetails details) {
    // Ao terminar o drag, avisar o pai que o modelo mudou
    widget.onChanged(widget.note.copyWith(position: _pos, width: _w, height: _h, rotation: _rotation));
  }

  void _onHandleStart(DragStartDetails details) {
    final rb = context.findRenderObject() as RenderBox?;
    if (rb == null) return;
    _startW = _w;
    _startH = _h;
    _startRotation = _rotation;
    // Calcular o centro global do widget (levando em conta o offset vertical
    // que reservámos para o handle de rotação) — usado para medir distâncias
    // do corner handle ao centro e assim calcular o scale uniforme.
    _centerGlobal = rb.localToGlobal(Offset(_w / 2, _rotateHandleDistance / 2 + _h / 2));
    _handleStartDist = (details.globalPosition - _centerGlobal).distance;
  }

  void _onHandleUpdate(DragUpdateDetails details) {
    final rb = context.findRenderObject() as RenderBox?;
    if (rb == null || _handleStartDist == 0) return;
    final newDist = (details.globalPosition - _centerGlobal).distance;
    final scale = (newDist / _handleStartDist).isFinite ? newDist / _handleStartDist : 1.0;
    final maxSide = math.max(widget.canvasSize.width, widget.canvasSize.height);
    final nw = (_startW * scale).clamp(_minSize, maxSide);
    final nh = (_startH * scale).clamp(_minSize, maxSide);
    setState(() {
      _w = nw;
      _h = nh;
    });
  }

  void _onHandleEnd(DragEndDetails details) {
    // Ao terminar o redimensionamento, informar o pai (persistência/undo)
    widget.onChanged(widget.note.copyWith(width: _w, height: _h, rotation: _rotation));
  }

  late double _startAngle;

  void _onRotateStart(DragStartDetails details) {
    final rb = context.findRenderObject() as RenderBox?;
    if (rb == null) return;
    // Igual que no corner-handle, precisamos do centro global para calcular
    // o ângulo inicial entre o toque e o centro do widget.
    _centerGlobal = rb.localToGlobal(Offset(_w / 2, _rotateHandleDistance / 2 + _h / 2));
    _startAngle = math.atan2(details.globalPosition.dy - _centerGlobal.dy, details.globalPosition.dx - _centerGlobal.dx);
    _startRotation = _rotation;
  }

  void _onRotateUpdate(DragUpdateDetails details) {
    final angle = math.atan2(details.globalPosition.dy - _centerGlobal.dy, details.globalPosition.dx - _centerGlobal.dx);
    final delta = angle - _startAngle;
    setState(() {
      _rotation = _startRotation + delta;
    });
  }

  void _onRotateEnd(DragEndDetails details) {
    // Comunicar alteração de rotação ao pai
    widget.onChanged(widget.note.copyWith(rotation: _rotation));
  }

  Widget _buildHandle(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: _onHandleStart,
        onPanUpdate: _onHandleUpdate,
        onPanEnd: _onHandleEnd,
        child: SizedBox(
          width: _handleTouchSize,
          height: _handleTouchSize,
          child: Center(
            child: Container(
              width: _handleVisualSize,
              height: _handleVisualSize,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.2),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pin = 8.0;
    final maxLeft = math.max(0.0, widget.canvasSize.width - _w - pin);
    final maxTop = math.max(0.0, widget.canvasSize.height - _h - pin);
    //Tamanhos do botão de apagar em função do tamanjo da imagem.
    //Aárea de toque é ligeiramente maior para acessibilidade.
    final double minDelete = 24.0;
    final double maxDelete = 64.0;
    final double deleteVisual = (math.min(_w, _h) * 0.18).clamp(minDelete, maxDelete);
    final double deleteTouch = deleteVisual + 8.0; // extra hit area

    return Positioned(
      left: (_pos.dx - _w / 2).clamp(0, maxLeft),
      top: (_pos.dy - _h / 2).clamp(0, maxTop),
      width: _w,
      height: _h + _rotateHandleDistance,
      child: GestureDetector(
    // Tap alterna a seleção (mostra/esconde handles). onPanStart vazio é
    // mantido porque o GestureDetector principal usa onPanUpdate/onPanEnd.
    onTap: () => setState(() => _selected = !_selected),
    onPanStart: (_) {},
        onPanUpdate: _onDragUpdate,
        onPanEnd: _onDragEnd,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: _rotateHandleDistance / 2,
              width: _w,
              height: _h,
              child: Transform.rotate(
                angle: _rotation,
                alignment: Alignment.center,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(widget.note.filePath),
                    width: _w,
                    height: _h,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, error, stack) => Container(
                      color: Colors.grey.shade200,
                      child: const Center(child: Icon(Icons.broken_image)),
                    ),
                  ),
                ),
              ),
            ),
            if (_selected)
            //Camada de seleção com handles e botão de apagar.
              Positioned(
                left: 0,
                top: _rotateHandleDistance / 2,
                width: _w,
                height: _h,
                child: Transform.rotate(
                  angle: _rotation,
                  alignment: Alignment.center,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                            ),
                          ),
                        ),
                      ),
                      if (widget.onDelete != null)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: SizedBox(
                            width: deleteTouch,
                            height: deleteTouch,
                            child: Center(
                              child: Material(
                                color: Colors.redAccent,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: widget.onDelete,
                                  child: SizedBox(
                                    width: deleteVisual,
                                    height: deleteVisual,
                                    child: Center(
                                      child: Icon(
                                        Icons.close,
                                        size: (deleteVisual * 0.5).clamp(12.0, 28.0),
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        //Handles de redimensionamento
                      Positioned(
                        left: -_handleTouchSize / 2,
                        top: -_handleTouchSize / 2,
                        child: _buildHandle(Alignment.topLeft),
                      ),
                      Positioned(
                        right: -_handleTouchSize / 2,
                        top: -_handleTouchSize / 2,
                        child: _buildHandle(Alignment.topRight),
                      ),
                      Positioned(
                        right: -_handleTouchSize / 2,
                        bottom: -_handleTouchSize / 2,
                        child: _buildHandle(Alignment.bottomRight),
                      ),
                      Positioned(
                        left: -_handleTouchSize / 2,
                        bottom: -_handleTouchSize / 2,
                        child: _buildHandle(Alignment.bottomLeft),
                      ),
                      Positioned(
                        left: (_w / 2) - (_handleTouchSize / 2),
                        top: -(_handleTouchSize / 2) - 4,
                        child: GestureDetector(
                          onPanStart: _onRotateStart,
                          onPanUpdate: _onRotateUpdate,
                          onPanEnd: _onRotateEnd,
                          child: SizedBox(
                            width: _handleTouchSize,
                            height: _handleTouchSize,
                            child: Center(
                              child: Container(
                                width: _handleVisualSize,
                                height: _handleVisualSize,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.2),
                                ),
                                child: const Icon(Icons.rotate_right, size: 12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
