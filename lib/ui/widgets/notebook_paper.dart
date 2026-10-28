import 'package:flutter/material.dart';
import '../../models/notebook_model.dart';

/// Shared by the creation previews and the writing surface.
class NotebookPaper extends StatelessWidget {
  const NotebookPaper({super.key, required this.style, this.spacing = 28})
    : assert(spacing > 0);

  final NotebookPaperStyle style;
  final double spacing;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _NotebookPaperPainter(style: style, spacing: spacing),
    child: const SizedBox.expand(),
  );
}

class _NotebookPaperPainter extends CustomPainter {
  const _NotebookPaperPainter({required this.style, required this.spacing});

  final NotebookPaperStyle style;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    if (style == NotebookPaperStyle.plain) return;

    final rule = Paint()
      ..color = const Color(0xFFCFDDEB)
      ..strokeWidth = 0.8;
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
    }
    if (style == NotebookPaperStyle.grid) {
      for (double x = spacing; x < size.width; x += spacing) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), rule);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NotebookPaperPainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.spacing != spacing;
}
