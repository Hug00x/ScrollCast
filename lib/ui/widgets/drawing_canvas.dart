import 'dart:ui';
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

  const DrawingCanvas({
    super.key,
    required this.strokes,
    required this.mode,
    required this.strokeWidth,
    required this.strokeColor,
    required this.onStrokeEnd,
    this.onPointerCountChanged,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  final _activePoints = <int, Offset>{}; // pointer -> pos
  final _currentLine = <Offset>[];

  // borracha
  static const double _eraserRadius = 18;

  void _notifyCount() => widget.onPointerCountChanged?.call(_activePoints.length);

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) {
        _activePoints[e.pointer] = e.localPosition;
        _notifyCount();
        if (_activePoints.length == 1 && widget.mode != StrokeMode.eraser) {
          _currentLine
            ..clear()
            ..add(e.localPosition);
          setState(() {});
        }
      },
      onPointerMove: (e) {
        _activePoints[e.pointer] = e.localPosition;

        if (_activePoints.length == 1) {
          if (widget.mode == StrokeMode.eraser) {
            // apaga segmentos por proximidade
            _eraseAt(e.localPosition);
          } else {
            // desenhar em tempo real
            _currentLine.add(e.localPosition);
          }
          setState(() {});
        } else {
          // 2+ dedos => não desenhar (deixa o InteractiveViewer trabalhar)
          _currentLine.clear();
        }
      },
      onPointerUp: (e) async {
        _activePoints.remove(e.pointer);
        _notifyCount();

        if (_currentLine.length > 1 && widget.mode != StrokeMode.eraser) {
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
      },
      onPointerCancel: (e) {
        _activePoints.remove(e.pointer);
        _currentLine.clear();
        _notifyCount();
        setState(() {});
      },
      child: CustomPaint(
        painter: _CanvasPainter(
          strokes: widget.strokes,
          previewLine: _currentLine,
          eraserRadius: widget.mode == StrokeMode.eraser ? _eraserRadius : 0,
        ),
      ),
    );
  }

  void _eraseAt(Offset where) {
    // remove segmentos “near” a 'where'
    for (int i = widget.strokes.length - 1; i >= 0; i--) {
      final s = widget.strokes[i];
      // só apaga se não for marca-texto (senão ficava estranho).
      if (s.mode == StrokeMode.highlighter || s.points.length < 2) continue;

      final newPoints = <Offset>[];
      for (int j = 0; j < s.points.length - 1; j++) {
        final a = s.points[j];
        final b = s.points[j + 1];
        // distância ponto-segmento
        final d = _distancePointToSegment(where, a, b);
        if (d > _eraserRadius) {
          newPoints.add(a);
        } else {
          // corta aqui: se houver bloco antes, substitui stroke por dois
          if (newPoints.length >= 2) {
            final kept = Stroke(
              points: List<Offset>.from(newPoints),
              width: s.width,
              color: s.color,
              mode: s.mode,
            );
            widget.strokes[i] = kept;
            // e duplica o resto noutro stroke
            final rest = s.points.sublist(j + 1);
            if (rest.length >= 2) {
              widget.strokes.insert(
                i + 1,
                Stroke(points: rest, width: s.width, color: s.color, mode: s.mode),
              );
            }
            return;
          } else {
            // nada antes: só fica o resto
            final rest = s.points.sublist(j + 1);
            if (rest.length >= 2) {
              widget.strokes[i] = Stroke(points: rest, width: s.width, color: s.color, mode: s.mode);
            } else {
              widget.strokes.removeAt(i);
            }
            return;
          }
        }
      }
      // se passou o loop e nada foi apagado, manter o último ponto
      newPoints.add(s.points.last);
      widget.strokes[i] = Stroke(points: newPoints, width: s.width, color: s.color, mode: s.mode);
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
  final double eraserRadius;

  _CanvasPainter({
    required this.strokes,
    required this.previewLine,
    required this.eraserRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      if (s.points.length < 2) continue;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.width
        ..color = Color(s.color).withOpacity(s.mode == StrokeMode.highlighter ? 0.35 : 1.0);
      for (int i = 0; i < s.points.length - 1; i++) {
        canvas.drawLine(s.points[i], s.points[i + 1], p);
      }
    }

    if (previewLine.length >= 2) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = strokes.isNotEmpty ? strokes.last.width : 3
        ..color = const Color(0xFF00FF00);
      for (int i = 0; i < previewLine.length - 1; i++) {
        canvas.drawLine(previewLine[i], previewLine[i + 1], p);
      }
    }

    if (eraserRadius > 0) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x80FFFFFF);
      // opcional: desenhar o “cursor” de borracha se quiseres
      // canvas.drawCircle(cursor, eraserRadius, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter old) =>
      old.strokes != strokes ||
      old.previewLine != previewLine ||
      old.eraserRadius != eraserRadius;
}
