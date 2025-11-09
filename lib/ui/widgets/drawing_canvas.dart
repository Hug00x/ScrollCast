import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../models/annotations.dart';

typedef StrokeEnd = Future<void> Function(Stroke stroke);
typedef PointerCountChanged = void Function(int count);

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

  // >>> NOVO: se true, só caneta (stylus) pode desenhar; dedos são ignorados
  final bool stylusOnly;

  // >>> NOVO: callback quando stylus toca/levanta
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
  final _activePoints = <int, Offset>{}; // pointer -> pos
  // todos os pointers (aceites ou não) — usado para contar (p.ex. 2 dedos => zoom)
  final _allPoints = <int, Offset>{};
  final _currentLine = <Offset>[];

  // rastreia quais pointers são stylus
  final _stylusPointers = <int>{};

  // preview da borracha
  Offset? _eraserCenter;

  // raio base (caso não venha do toolbar)
  static const double _fallbackEraserRadius = 18;

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
      onPointerDown: (e) {
        // marca stylus
        if (_isStylus(e)) {
          _stylusPointers.add(e.pointer);
          widget.onStylusContact?.call(true);
        }

        // sempre contar o pointer (p.ex., 2 dedos -> zoom), mesmo que não seja aceite para desenhar
        _allPoints[e.pointer] = e.localPosition;
        if (!_shouldAcceptDown(e)) {
          _notifyCount();
          return;
        }

        // apenas pointers aceite para desenho vão para _activePoints
        _activePoints[e.pointer] = e.localPosition;
        _notifyCount();

        if (_activePoints.length == 1) {
          if (isEraser) {
            // inform the parent that erasing is about to start so it can snapshot for undo
            widget.onBeforeErase?.call();
            _eraserCenter = e.localPosition;
          } else {
            _currentLine
              ..clear()
              ..add(e.localPosition);
          }
          setState(() {});
        }
      },
      onPointerMove: (e) {
        // atualiza posição de todos os pointers para contagem/HUD
        _allPoints[e.pointer] = e.localPosition;

        // se o pointer não foi aceite (ex.: dedo em modo stylusOnly), ignora
        final wasAccepted = _activePoints.containsKey(e.pointer);
        if (!wasAccepted && widget.stylusOnly) return;

        // actualiza posição apenas dos pointers aceite para desenho
        _activePoints[e.pointer] = e.localPosition;

        if (_activePoints.length == 1) {
          if (isEraser) {
            _eraserCenter = e.localPosition;
            _eraseAt(e.localPosition); // pode disparar onStrokesChanged
          } else {
            _currentLine.add(e.localPosition);
          }
          setState(() {});
        } else {
          // 2+ dedos => não desenhar (deixa o InteractiveViewer trabalhar)
          _currentLine.clear();
        }
      },
      onPointerUp: (e) async {
        // stylus up?
        if (_stylusPointers.remove(e.pointer) && _stylusPointers.isEmpty) {
          widget.onStylusContact?.call(false);
        }

        final wasAccepted = _activePoints.remove(e.pointer) != null;
        _allPoints.remove(e.pointer);
        _notifyCount();

        if (wasAccepted && _currentLine.length > 1 && !isEraser) {
          final stroke = Stroke(
            points: List<Offset>.from(_currentLine),
            width: widget.mode == StrokeMode.highlighter ? widget.strokeWidth * 1.35 : widget.strokeWidth,
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

      final newPoints = <Offset>[];
      bool cut = false;

      for (int j = 0; j < s.points.length - 1; j++) {
        final a = s.points[j];
        final b = s.points[j + 1];
        final d = _distancePointToSegment(where, a, b);

        if (d > radius) {
          newPoints.add(a);
        } else {
          // corta aqui
          cut = true;
          anyChange = true;
          if (newPoints.length >= 2) {
            widget.strokes[i] = Stroke(
              points: List<Offset>.from(newPoints),
              width: s.width,
              color: s.color,
              mode: s.mode,
            );
            final rest = s.points.sublist(j + 1);
            if (rest.length >= 2) {
              widget.strokes.insert(
                i + 1,
                Stroke(points: rest, width: s.width, color: s.color, mode: s.mode),
              );
            }
          } else {
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
        // não houve corte no meio: manter último ponto (ainda assim altera o stroke)
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
    // strokes finalizados
    for (final s in strokes) {
      if (s.points.length < 2) continue;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.width
  ..color = Color(s.color).withAlpha(((s.mode == StrokeMode.highlighter ? 0.35 : 1.0) * 255).round());
      for (int i = 0; i < s.points.length - 1; i++) {
        canvas.drawLine(s.points[i], s.points[i + 1], p);
      }
    }

    // traço em tempo real
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

    // preview da borracha
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
