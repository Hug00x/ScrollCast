import 'package:flutter/material.dart';
import '../../models/annotations.dart';

class AnnotationToolbar extends StatelessWidget {
  const AnnotationToolbar({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.width,
    required this.onWidthChanged,
    required this.color,
    required this.onColorChanged,
    this.onUndo,
    this.onRedo,
  });

  final StrokeMode mode;
  final ValueChanged<StrokeMode> onModeChanged;

  final double width;
  final ValueChanged<double> onWidthChanged;

  final int color; // ARGB
  final ValueChanged<int> onColorChanged;

  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surface.withOpacity(0.6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Linha 1: modos + undo/redo
            Row(
              children: [
                _ModeButton(
                  selected: mode == StrokeMode.pen,
                  icon: Icons.brush_rounded,
                  label: 'Desenhar',
                  onTap: () => onModeChanged(StrokeMode.pen),
                ),
                const SizedBox(width: 8),
                _ModeButton(
                  selected: mode == StrokeMode.eraser,
                  icon: Icons.auto_fix_off_rounded,
                  label: 'Borracha',
                  onTap: () => onModeChanged(StrokeMode.eraser),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Anular',
                  onPressed: onUndo,
                  icon: const Icon(Icons.undo_rounded),
                ),
                IconButton(
                  tooltip: 'Refazer',
                  onPressed: onRedo,
                  icon: const Icon(Icons.redo_rounded),
                ),
                const Spacer(),
                // espelho da cor e espessura atuais
                _StrokePreview(color: color, width: width),
              ],
            ),

            const SizedBox(height: 8),

            // Linha 2: paleta de cores
            _ColorPalette(
              selected: color,
              onChanged: onColorChanged,
            ),

            const SizedBox(height: 4),

            // Linha 3: espessura
            Row(
              children: [
                const Icon(Icons.horizontal_rule_rounded, size: 18),
                Expanded(
                  child: Slider(
                    value: width.clamp(1, 24),
                    min: 1,
                    max: 24,
                    onChanged: onWidthChanged,
                  ),
                ),
                const Icon(Icons.format_size_rounded, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withOpacity(0.15) : Colors.transparent,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: selected ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorPalette extends StatelessWidget {
  const _ColorPalette({
    required this.selected,
    required this.onChanged,
  });

  final int selected;
  final ValueChanged<int> onChanged;

  // Paleta “ScrollCast”
 static const _colors = <int>[
  0xFFE53935, // vermelho forte → alertas, urgência
  0xFFFB8C00, // laranja vivo → categorias principais
  0xFFFDD835, // amarelo limão → destaques
  0xFF43A047, // verde vibrante → tarefas feitas
  0xFF00ACC1, // azul ciano → links, referências
  0xFF8E24AA, // roxo elétrico → extras, abstrações
  0xFF000000, // preto → texto base
  0xFFFFFFFF, // branco → contraste em dark mode
];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, i) {
          final c = _colors[i];
          final isSel = c == selected;
          return GestureDetector(
            onTap: () => onChanged(c),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSel ? scheme.primary : scheme.outlineVariant,
                  width: isSel ? 2 : 1,
                ),
                color: Color(c),
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: _colors.length,
      ),
    );
  }
}

class _StrokePreview extends StatelessWidget {
  const _StrokePreview({required this.color, required this.width});
  final int color;
  final double width;

  @override
  Widget build(BuildContext context) {
    final w = width.clamp(1, 24);
    return Row(
      children: [
        Text('${w.toInt()}px', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(width: 8),
        Container(
          width: 48,
          height: 20,
          alignment: Alignment.centerLeft,
          child: CustomPaint(
            painter: _StrokeDemoPainter(Color(color), w.toDouble()),
          ),
        ),
      ],
    );
  }
}

class _StrokeDemoPainter extends CustomPainter {
  _StrokeDemoPainter(this.color, this.width);
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final y = size.height / 2;
    canvas.drawLine(Offset(2, y), Offset(size.width - 2, y), p);
  }

  @override
  bool shouldRepaint(covariant _StrokeDemoPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.width != width;
}
