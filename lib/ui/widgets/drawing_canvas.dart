import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../models/annotations.dart';

/*
  drawing_canvas.dart

  Propósito geral:
  - Widget de desenho que fornece uma superfície para criar traços (strokes)
    com suporte a caneta e dedo, bem como uma ferramenta de borracha
    que corta traços existentes.
  - Implementa toda a lógica de captura de ponteiros, aceita
    múltiplos pointers para contagem/gestos, e expõe callbacks para o pai
    persistir traços (onStrokeEnd) ou reagir a mudanças (onStrokesChanged).
  - O build usa um `Listener` para receber eventos brutos de ponteiro e um
    `CustomPaint` para desenhar os traços finalizados e pré-visualizações
    em tempo real.

  Observações de design:
  - A borracha (eraser) não apenas apaga pontos mas pode 'cortar' um traço
    em duas partes quando o ponto de corte ocorre no meio do traço.
  - Esta implementação mantém a lógica de desenho separada do painter. O
    `CustomPainter` é puramente declarativo: desenha com base no estado.
*/


// Tipo para notificar ao pai que um novo stroke foi finalizado e deve ser
// persistido/encaixado na lista de strokes.
typedef StrokeEnd = Future<void> Function(Stroke stroke);

// Notifica o pai sobre o número atual de pointers em contacto. Útil para
// decidir quando mostrar/ocultar controlos que dependem da contagem de dedos.
typedef PointerCountChanged = void Function(int count);

// Widget principal que encapsula a superfície de desenho.
// - Renderiza os strokes existentes fornecidos pelo pai.
// - Captura eventos de ponteiro e constrói um preview em tempo real.
class DrawingCanvas extends StatefulWidget {
  final List<Stroke> strokes;
  final StrokeMode mode;
  final double strokeWidth;
  final int strokeColor;
  final StrokeEnd onStrokeEnd;
  final PointerCountChanged? onPointerCountChanged;

  // raio visual da borracha (recebe do toolbar)
  final double? eraserWidthPreview;

  // avisa o pai quando a borracha modificar os traços
  final VoidCallback? onStrokesChanged;
  /// Called once when the eraser interaction starts. Use to snapshot state for undo.
  final VoidCallback? onBeforeErase;

  // Se true, só caneta (stylus) pode desenhar; dedos são ignorados
  final bool stylusOnly;

  // Callback quando stylus toca/levanta
  final void Function(bool isDown)? onStylusContact;

  const DrawingCanvas({
    super.key,
    required this.strokes,
    required this.mode,
    required this.strokeWidth,
    required this.strokeColor,
    required this.onStrokeEnd,
    this.onPointerCountChanged,
    this.eraserWidthPreview,
    this.onStrokesChanged,
    this.onBeforeErase,
    this.stylusOnly = false,
    this.onStylusContact,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {

  // Mapa de pointers atualmente ativos para desenho
  // Apenas pointers aceites para desenhar (por exemplo, em stylusOnly dedos não
  // entrarão aqui, mas serão contados em _allPoints).
  final _activePoints = <int, Offset>{};

  // Todos os pointers vistos (aceites ou não). Usado para notificar a contagem
  // ao pai (p.ex. 2 dedos para zoom). Mantenho isto para separar contagem de
  // entrada efetiva de desenho.
  final _allPoints = <int, Offset>{};

  // Linha construída para o stroke em progresso quando há
  // exatamente 1 pointer a desenhar. Resetada após completar o stroke.
  final _currentLine = <Offset>[];

  // Conjunto de pointers identificados como stylus para enviar eventos de
  // contacto (onStylusContact) assim que todos levantarem/pousarem.
  final _stylusPointers = <int>{};

  // Centro do preview da borracha (quando em modo eraser). Usado pelo painter
  // para mostrar uma circunferência indicadora.
  Offset? _eraserCenter;

  // Raio padrão para a borracha quando o toolbar não forneceu um valor.
  static const double _fallbackEraserRadius = 18;

  // Helper para notificar o pai sobre a contagem atual de pointers.
  void _notifyCount() => widget.onPointerCountChanged?.call(_allPoints.length);


  bool _isStylus(PointerDownEvent e) =>
      e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;

  bool _shouldAcceptDown(PointerDownEvent e) {
    if (!widget.stylusOnly) return true;
    return _isStylus(e); // em modo “só caneta”, ignora dedos
  }

  @override
  Widget build(BuildContext context) {
    final isEraser = widget.mode == StrokeMode.eraser;

    return Listener(
      behavior: HitTestBehavior.opaque,
      // Pointer down handler:
      // - Regista se o pointer veio de uma stylus e notifica o pai quando a
      //   stylus entra em contacto (onStylusContact(true)).
      // - Mantém _allPoints para contar todos os pointers mesmo que não sejam
      //   aceites para desenhar (ex.: modo stylusOnly). Se o pointer é aceite
      //   para desenhar, adiciona-o a _activePoints e inicia a pré-visualização
      //   do stroke ou da borracha.
      onPointerDown: (e) {
        // marca stylus e notifica contacto se aplicável
        if (_isStylus(e)) {
          _stylusPointers.add(e.pointer);
          widget.onStylusContact?.call(true);
        }

        // contar sempre para a lógica de HUD/gestos
        _allPoints[e.pointer] = e.localPosition;
        if (!_shouldAcceptDown(e)) {
          _notifyCount();
          return;
        }

        // pointer aceite para desenho
        _activePoints[e.pointer] = e.localPosition;
        _notifyCount();

        if (_activePoints.length == 1) {
          // se apenas 1 pointer, começamos preview de stroke ou borracha
          if (isEraser) {
            // avisa o pai que a interacção de apagar vai começar (para  snapshotmde undo)
            widget.onBeforeErase?.call();
            _eraserCenter = e.localPosition;
          } else {
            // iniciar a linha de pré-visualização
            _currentLine
              ..clear()
              ..add(e.localPosition);
          }
          setState(() {});
        }
      },
      onPointerMove: (e) {
        // Move handler:
        // - Atualiza _allPoints para manter contagem correta
        // - Se o pointer foi aceite para desenho atualiza a sua posição em
        //   _activePoints e altera o preview/eraser conforme apropriado.
        _allPoints[e.pointer] = e.localPosition;

        final wasAccepted = _activePoints.containsKey(e.pointer);
        if (!wasAccepted && widget.stylusOnly) return; // ignorar movimentos de dedos se só caneta

        _activePoints[e.pointer] = e.localPosition;

        if (_activePoints.length == 1) {
          // modo single-pointer => desenhar ou apagar
          if (isEraser) {
            _eraserCenter = e.localPosition;
            _eraseAt(e.localPosition); // operação de apagar/cortar
          } else {
            _currentLine.add(e.localPosition);
          }
          setState(() {});
        } else {
          _currentLine.clear();
        }
      },
      onPointerUp: (e) async {
        // Pointer up:
        // - Se o pointer pertencia a uma stylus atualiza _stylusPointers e
        //   notifica onStylusContact(false) quando não houver stylus ativos.
        // - Remove o pointer de _activePoints e _allPoints e notifica o pai
        //   sobre a nova contagem.
        if (_stylusPointers.remove(e.pointer) && _stylusPointers.isEmpty) {
          widget.onStylusContact?.call(false);
        }

        final wasAccepted = _activePoints.remove(e.pointer) != null;
        _allPoints.remove(e.pointer);
        _notifyCount();

        // Se o pointer era responsável pelo stroke em progresso e houver pontos
        // suficientes, acabar o stroke e avisar o pai (persistência/undo).
        if (wasAccepted && _currentLine.length > 1 && !isEraser) {
          final stroke = Stroke(
            points: List<Offset>.from(_currentLine),
            width: widget.strokeWidth,
            color: widget.strokeColor,
            mode: widget.mode,
          );
          _currentLine.clear();
          await widget.onStrokeEnd(stroke);
        } else {
          _currentLine.clear();
          setState(() {});
        }
        _eraserCenter = null;
      },
      onPointerCancel: (e) {
        // Cancelamento abrupto: limpar estado relativo ao pointer
        _stylusPointers.remove(e.pointer);
        _activePoints.remove(e.pointer);
        _allPoints.remove(e.pointer);
        _currentLine.clear();
        _eraserCenter = null;
        _notifyCount();
        setState(() {});
      },
      child: CustomPaint(
        painter: _CanvasPainter(
          strokes: widget.strokes,
          previewLine: _currentLine,
          previewColor: widget.strokeColor,
          previewWidth: widget.strokeWidth,
          eraserCenter: _eraserCenter,
          eraserRadius: (widget.eraserWidthPreview ?? _fallbackEraserRadius),
          showEraser: isEraser,
        ),
      ),
    );
  }

  void _eraseAt(Offset where) {
    final radius = (widget.eraserWidthPreview ?? _fallbackEraserRadius);
    bool anyChange = false;

    for (int i = widget.strokes.length - 1; i >= 0; i--) {
      final s = widget.strokes[i];
      if (s.points.length < 2) continue;

      // Lógica de corte da borracha:
      // - Iteramos os segmentos do stroke e calculamos a distância do ponto
      //   (where) ao segmento. Se estiver dentro do raio consideramos que
      //   houve um corte e partimos o stroke em partes apropriadas.
      final newPoints = <Offset>[];
      bool cut = false;

      for (int j = 0; j < s.points.length - 1; j++) {
        final a = s.points[j];
        final b = s.points[j + 1];
        final d = _distancePointToSegment(where, a, b);

        if (d > radius) {
          // segmento intacto: manter o ponto de começo
          newPoints.add(a);
        } else {
          // O ponto de borracha atingiu este segmento: efetuar corte
          cut = true;
          anyChange = true;

          if (newPoints.length >= 2) {
            // Parte anterior tem pontos suficientes: mantenho como primeira parte
            widget.strokes[i] = Stroke(
              points: List<Offset>.from(newPoints),
              width: s.width,
              color: s.color,
              mode: s.mode,
            );
            final rest = s.points.sublist(j + 1);
            if (rest.length >= 2) {
              // Parte restante é válida: inserimos como novo stroke após o atual
              widget.strokes.insert(
                i + 1,
                Stroke(points: rest, width: s.width, color: s.color, mode: s.mode),
              );
            }
          } else {
            // Não havia pontos suficientes antes do corte: a parte seguinte
            // pode tornar-se o stroke atual ou removemos se inválida.
            final rest = s.points.sublist(j + 1);
            if (rest.length >= 2) {
              widget.strokes[i] = Stroke(points: rest, width: s.width, color: s.color, mode: s.mode);
            } else {
              widget.strokes.removeAt(i);
            }
          }
          break;
        }
      }

      if (!cut) {
        // Se não houve corte, ainda assim atualizamos o stroke para manter a
        // consistência da estrutura (mantemos o último ponto e marcamos
        // alteração para disparar onStrokesChanged).
        newPoints.add(s.points.last);
        widget.strokes[i] = Stroke(points: newPoints, width: s.width, color: s.color, mode: s.mode);
        anyChange = true;
      }
    }

    if (anyChange) {
      widget.onStrokesChanged?.call();
    }
  }

  double _distancePointToSegment(Offset p, Offset a, Offset b) {
    final ap = p - a;
    final ab = b - a;
    final ab2 = ab.dx * ab.dx + ab.dy * ab.dy;
    final dot = ap.dx * ab.dx + ap.dy * ab.dy;
    final t = ab2 == 0 ? 0.0 : (dot / ab2).clamp(0.0, 1.0);
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distance;
  }
}

class _CanvasPainter extends CustomPainter {
  final List<Stroke> strokes;
  final List<Offset> previewLine;
  final int previewColor;
  final double previewWidth;

  // pré-visualização borracha
  final bool showEraser;
  final Offset? eraserCenter;
  final double eraserRadius;

  _CanvasPainter({
    required this.strokes,
    required this.previewLine,
    required this.previewColor,
    required this.previewWidth,
    required this.showEraser,
    required this.eraserCenter,
    required this.eraserRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Desenhar todos os strokes já finalizados.
    // Cada stroke é desenhado como várias linhas entre pontos consecutivos.
    for (final s in strokes) {
      if (s.points.length < 2) continue;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.width
        ..color = Color(s.color);
      for (int i = 0; i < s.points.length - 1; i++) {
        canvas.drawLine(s.points[i], s.points[i + 1], p);
      }
    }

    // Desenhar o preview do stroke em progresso (se houver pelo menos 2 pontos)
    if (previewLine.length >= 2) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = previewWidth
        ..color = Color(previewColor);
      for (int i = 0; i < previewLine.length - 1; i++) {
        canvas.drawLine(previewLine[i], previewLine[i + 1], p);
      }
    }

    // Desenhar o indicador da borracha quando ativo: um círculo preenchido
    // com um anel exterior para melhor visibilidade.
    if (showEraser && eraserCenter != null) {
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0x22000000);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xA0FFFFFF);
      canvas.drawCircle(eraserCenter!, eraserRadius, fill);
      canvas.drawCircle(eraserCenter!, eraserRadius, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter old) =>
      old.strokes != strokes ||
      old.previewLine != previewLine ||
      old.previewColor != previewColor ||
      old.previewWidth != previewWidth ||
      old.showEraser != showEraser ||
      old.eraserCenter != eraserCenter ||
      old.eraserRadius != eraserRadius;
}
