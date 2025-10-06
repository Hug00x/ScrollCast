import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
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
    required this.eraserWidth,
    required this.onEraserWidthChanged,
  });

  final StrokeMode mode;
  final ValueChanged<StrokeMode> onModeChanged;

  final double width;
  final ValueChanged<double> onWidthChanged;

  final int color; // ARGB
  final ValueChanged<int> onColorChanged;

  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  final double eraserWidth;
  final ValueChanged<double> onEraserWidthChanged;

  Future<void> _pickColor(BuildContext context) async {
    Color temp = Color(color);
    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Escolher cor'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: temp,
            onColorChanged: (c) => temp = c,
            enableAlpha: false,
            portraitOnly: true,
            pickerAreaBorderRadius: const BorderRadius.all(Radius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, temp), child: const Text('OK')),
        ],
      ),
    );
    if (picked != null) onColorChanged(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEraser = mode == StrokeMode.eraser;

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
            // LINHA 1 — modos + undo/redo + preview (com scroll horizontal p/ evitar overflow)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _ModeButton(
                    selected: mode == StrokeMode.pen,
                    icon: Icons.brush_rounded,
                    label: 'Desenhar',
                    onTap: () => onModeChanged(StrokeMode.pen),
                  ),
                  const SizedBox(width: 8),
                  _ModeButton(
                    selected: isEraser,
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
                  const SizedBox(width: 8),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // LINHA 2 — paleta + botão do espectro JUNTOS
            _ColorPaletteWithPicker(
              selected: color,
              onChanged: onColorChanged,
              onPickMore: () => _pickColor(context),
            ),

            const SizedBox(height: 4),

            // LINHA 3 — espessura (pincel/borracha)
            Row(
              children: [
                const Icon(Icons.horizontal_rule_rounded, size: 18),
                Expanded(
                  child: Slider(
                    value: (isEraser ? eraserWidth : width).clamp(1, 48),
                    min: 1,
                    max: 48,
                    onChanged: isEraser ? onEraserWidthChanged : onWidthChanged,
                  ),
                ),
                const Icon(Icons.add_rounded, size: 18),
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
          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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

/// Paleta de cores + botão de espectro na mesma fila.
class _ColorPaletteWithPicker extends StatelessWidget {
  const _ColorPaletteWithPicker({
    required this.selected,
    required this.onChanged,
    required this.onPickMore,
  });

  final int selected;
  final ValueChanged<int> onChanged;
  final VoidCallback onPickMore;

  // Paleta “ScrollCast”
  static const _colors = <int>[
    0xFFE53935, // vermelho
    0xFFFB8C00, // laranja
    0xFFFDD835, // amarelo
    0xFF43A047, // verde
    0xFF00ACC1, // ciano
    0xFF8E24AA, // roxo
    0xFF000000, // preto
    0xFFFFFFFF, // branco
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(right: 4),
        itemBuilder: (_, i) {
          // último “item virtual” é o botão de espectro
          if (i == _colors.length) {
            return Tooltip(
              message: 'Mais cores…',
              child: InkWell(
                onTap: onPickMore,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(selected), Color(selected).withOpacity(.7)],
                    ),
                    border: Border.all(color: scheme.onSurface.withOpacity(.15)),
                  ),
                  child: const Icon(Icons.palette_rounded, size: 18),
                ),
              ),
            );
          }

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
        itemCount: _colors.length + 1, // +1 para o botão de espectro
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
    final double w = width.clamp(1, 48).toDouble();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 8),
        SizedBox(
          width: 48,
          height: 20,
          child: CustomPaint(
            painter: _StrokeDemoPainter(Color(color), w),
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
