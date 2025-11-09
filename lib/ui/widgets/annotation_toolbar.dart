import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/services.dart';
import '../../models/annotations.dart';
import '../../main.dart';

// Forces input to uppercase (used for hex input)
class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final upper = newValue.text.toUpperCase();
    return TextEditingValue(text: upper, selection: newValue.selection);
  }
}

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
      this.canUndo = false,
      this.canRedo = false,
    this.enabled = true,
    this.showLabels = true,
    required this.eraserWidth,
    required this.onEraserWidthChanged,
    this.ownerId,
    this.ownerIsNotebook = false,
  });

  final StrokeMode mode;
  final ValueChanged<StrokeMode> onModeChanged;

  final double width;
  final ValueChanged<double> onWidthChanged;

  final int color; // ARGB
  final ValueChanged<int> onColorChanged;

  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool canUndo;
  final bool canRedo;
  final bool enabled;
  final bool showLabels;

  final double eraserWidth;
  final ValueChanged<double> onEraserWidthChanged;
  final String? ownerId;
  final bool ownerIsNotebook;

  Future<void> _pickColor(BuildContext context) async {
    Color temp = Color(color);
    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        String colorToHex(Color c) {
          // return RRGGBB
          final r = (c.red).toRadixString(16).padLeft(2, '0');
          final g = (c.green).toRadixString(16).padLeft(2, '0');
          final b = (c.blue).toRadixString(16).padLeft(2, '0');
          return (r + g + b).toUpperCase();
        }

  controller.text = colorToHex(temp);
  controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));

        return StatefulBuilder(builder: (ctx2, setState) {
          void setTempFromHex(String text) {
            final hex = text.replaceAll('#', '').replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
            if (hex.length >= 6) {
              final hex6 = hex.substring(0, 6).toUpperCase();
              try {
                final int val = int.parse(hex6, radix: 16);
                final Color c = Color(0xFF000000 | val);
                setState(() {
                  temp = c;
                  // keep controller uppercase and limited to 6
                  if (controller.text.toUpperCase() != hex6) {
                    controller.value = TextEditingValue(
                      text: hex6,
                      selection: TextSelection.collapsed(offset: hex6.length),
                    );
                  }
                });
              } catch (_) {}
            }
          }

          // When the user wants to edit the hex code we open a bottom sheet
          // so the keyboard is handled by the sheet and doesn't push the dialog
          // offscreen. The dialog itself stays fixed.
          Future<void> openHexEditor() async {
            final res = await showModalBottomSheet<String>(
              context: ctx2,
              isScrollControlled: true,
              builder: (ctx3) {
                final editController = TextEditingController(text: controller.text);
                return Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(ctx3).viewInsets.bottom),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Expanded(child: Text('Escolher código HEX', style: TextStyle(fontWeight: FontWeight.w600))),
                            IconButton(onPressed: () => Navigator.pop(ctx3), icon: const Icon(Icons.close)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: editController,
                          autofocus: true,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                            LengthLimitingTextInputFormatter(6),
                            _UpperCaseTextFormatter(),
                          ],
                          decoration: const InputDecoration(prefixText: '#', hintText: 'RRGGBB', counterText: ''),
                          onSubmitted: (v) => Navigator.pop(ctx3, v),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: () => Navigator.pop(ctx3, editController.text),
                                child: const Text('OK'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );

            if (res != null) {
              setTempFromHex(res);
            }
          }

          return AlertDialog(
            title: const Text('Escolher cor'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ColorPicker(
                    pickerColor: temp,
                    onColorChanged: (c) {
                      setState(() {
                        temp = c;
                        controller.text = colorToHex(c);
                      });
                    },
                    enableAlpha: false,
                    portraitOnly: true,
                    showLabel: false, // hide RGB/HSL fields
                    pickerAreaBorderRadius: const BorderRadius.all(Radius.circular(12)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: temp,
                          shape: BoxShape.circle,
                          border: Border.all(color: Theme.of(context).colorScheme.onSurface.withAlpha(0x22)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () => openHexEditor(),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                            decoration: BoxDecoration(
                              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '#${controller.text}',
                                    style: const TextStyle(fontFamily: 'monospace'),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.edit, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(ctx2, temp), child: const Text('OK')),
            ],
          );
        });
      },
    );
    if (picked != null) {
      // convert Color to ARGB int
      final int argb = picked.value & 0xFFFFFFFF;
      onColorChanged(argb);
      // persist recent color for this document if we have an owner id
      if (ownerId != null) {
        try {
          final db = ServiceLocator.instance.db;
          if (ownerIsNotebook) {
            final model = await db.getNotebookById(ownerId!);
            if (model != null) {
              final list = <int>[argb, ...model.recentColors.where((c) => c != argb)];
              final trimmed = list.take(8).toList();
              await db.upsertNotebook(model.copyWith(lastOpened: model.lastOpened, lastPage: model.lastPage, lastColors: trimmed));
            }
          } else {
            final model = await db.getPdfById(ownerId!);
            if (model != null) {
              final list = <int>[argb, ...model.recentColors.where((c) => c != argb)];
              final trimmed = list.take(8).toList();
              await db.upsertPdf(model.copyWith(lastOpened: model.lastOpened, lastPage: model.lastPage, recentColors: trimmed));
            }
          }
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEraser = mode == StrokeMode.eraser;

    return Material(
      color: Colors.transparent,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1.0 : 0.35,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              // avoid deprecated `withOpacity` on Color; use withAlpha for equivalent effect
              color: scheme.surface.withAlpha((0.6 * 255).round()),
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
                    enabled: enabled,
                  ),
                  const SizedBox(width: 8),
                  _ModeButton(
                    selected: isEraser,
                    icon: Icons.auto_fix_off_rounded,
                    label: 'Borracha',
                    onTap: () => onModeChanged(StrokeMode.eraser),
                    enabled: enabled,
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Anular',
                    onPressed: (canUndo && enabled) ? onUndo : null,
                    icon: const Icon(Icons.undo_rounded),
                  ),
                  IconButton(
                    tooltip: 'Refazer',
                    onPressed: (canRedo && enabled) ? onRedo : null,
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
              onChanged: (c) {
                if (!enabled) return;
                onColorChanged(c);
                // persist recent color for owner
                if (ownerId != null) {
                  () async {
                    try {
                      final db = ServiceLocator.instance.db;
                      if (ownerIsNotebook) {
                        final model = await db.getNotebookById(ownerId!);
                        if (model != null) {
                          final list = <int>[c, ...model.recentColors.where((x) => x != c)];
                          final trimmed = list.take(8).toList();
                          await db.upsertNotebook(model.copyWith(lastOpened: model.lastOpened, lastPage: model.lastPage, lastColors: trimmed));
                        }
                      } else {
                        final model = await db.getPdfById(ownerId!);
                        if (model != null) {
                          final list = <int>[c, ...model.recentColors.where((x) => x != c)];
                          final trimmed = list.take(8).toList();
                          await db.upsertPdf(model.copyWith(lastOpened: model.lastOpened, lastPage: model.lastPage, recentColors: trimmed));
                        }
                      }
                    } catch (_) {}
                  }();
                }
              },
              onPickMore: () { if (enabled) _pickColor(context); },
              onOpenRecent: () {
                if (!enabled || ownerId == null) return;
                // open recent colors sheet
                showModalBottomSheet<void>(
                  context: context,
                  builder: (ctx) => _RecentColorsSheet(ownerId: ownerId!, ownerIsNotebook: ownerIsNotebook, onSelect: (col) { if (enabled) onColorChanged(col); }),
                );
              },
              enabled: enabled,
            ),

            const SizedBox(height: 4),

            // LINHA 3 — espessura (pincel/borracha)
            Row(
              children: [
                const Icon(Icons.horizontal_rule_rounded, size: 18),
                    Expanded(
                    child: Slider(
                    value: (isEraser ? eraserWidth : width).clamp(1, 48).toDouble(),
                    min: 1,
                    max: 48,
                    onChanged: enabled ? (isEraser ? onEraserWidthChanged : onWidthChanged) : null,
                  ),
                ),
                const Icon(Icons.add_rounded, size: 18),
              ],
            ),
          ],
        ),
      ),
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
    this.enabled = true,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withAlpha((0.15 * 255).round()) : Colors.transparent,
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
    required this.onOpenRecent,
    this.enabled = true,
  });

  final int selected;
  final ValueChanged<int> onChanged;
  final VoidCallback onPickMore;
  final VoidCallback onOpenRecent;
  final bool enabled;

  // Paleta “ScrollCast”
  static const _colors = <int>[
    0xFFE53935, // vermelho
    0xFFFB8C00, // laranja
    0xFFFDD835, // amarelo
    0xFF43A047, // verde
    0xFF00ACC1, // ciano
    0xFF8E24AA, // roxo
    0xFF000000, // preto
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
          // virtual items: spectrum button and recent-colors button at the end
          if (i == _colors.length) {
            return Tooltip(
              message: 'Mais cores…',
              child: InkWell(
                onTap: enabled ? onPickMore : null,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 32,
                  height: 32,
                    decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(selected), Color(selected).withAlpha((0.7 * 255).round())],
                    ),
                    border: Border.all(color: scheme.onSurface.withAlpha((0.15 * 255).round())),
                  ),
                  child: const Icon(Icons.palette_rounded, size: 18),
                ),
              ),
            );
          }
          if (i == _colors.length + 1) {
            return Tooltip(
              message: 'Cores recentes',
              child: InkWell(
                onTap: enabled ? onOpenRecent : null,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.onSurface.withAlpha((0.15 * 255).round())),
                  ),
                  child: const Icon(Icons.history_rounded, size: 18),
                ),
              ),
            );
          }

          final c = _colors[i];
          final isSel = c == selected;
          return GestureDetector(
            onTap: enabled ? () => onChanged(c) : null,
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
  separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemCount: _colors.length + 2, // +1 para o botão de espectro +1 para o botão de cores recentes
      ),
    );
  }
}

// Note: preview painter removed because it wasn't referenced anywhere in the toolbar.
// Keeping the file focused on the toolbar UI reduces unused-element analyzer hints.

class _RecentColorsSheet extends StatefulWidget {
  const _RecentColorsSheet({required this.ownerId, required this.ownerIsNotebook, required this.onSelect});

  final String ownerId;
  final bool ownerIsNotebook;
  final ValueChanged<int> onSelect;

  @override
  State<_RecentColorsSheet> createState() => _RecentColorsSheetState();
}

class _RecentColorsSheetState extends State<_RecentColorsSheet> {
  List<int> _colors = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = ServiceLocator.instance.db;
      if (widget.ownerIsNotebook) {
        final m = await db.getNotebookById(widget.ownerId);
        if (m != null) _colors = List.of(m.recentColors);
      } else {
        final m = await db.getPdfById(widget.ownerId);
        if (m != null) _colors = List.of(m.recentColors);
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _clearAll() async {
    try {
      final db = ServiceLocator.instance.db;
      if (widget.ownerIsNotebook) {
        final m = await db.getNotebookById(widget.ownerId);
        if (m != null) await db.upsertNotebook(m.copyWith(lastOpened: m.lastOpened, lastPage: m.lastPage, lastColors: []));
      } else {
        final m = await db.getPdfById(widget.ownerId);
        if (m != null) await db.upsertPdf(m.copyWith(lastOpened: m.lastOpened, lastPage: m.lastPage, recentColors: []));
      }
    } catch (_) {}
    if (mounted) setState(() => _colors = []);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Cores recentes', style: TextStyle(fontWeight: FontWeight.w600))),
                IconButton(onPressed: _clearAll, icon: const Icon(Icons.delete_outline_rounded)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ],
            ),
            const SizedBox(height: 8),
            if (_colors.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Sem cores recentes para este documento.', style: TextStyle(color: cs.onSurfaceVariant)),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _colors.map((c) {
                  return GestureDetector(
                    onTap: () async {
                      // move selected to front and persist
                      final sel = c;
                      try {
                        final db = ServiceLocator.instance.db;
                        if (widget.ownerIsNotebook) {
                          final m = await db.getNotebookById(widget.ownerId);
                          if (m != null) {
                            final list = <int>[sel, ...m.recentColors.where((x) => x != sel)];
                            await db.upsertNotebook(m.copyWith(lastOpened: m.lastOpened, lastPage: m.lastPage, lastColors: list.take(8).toList()));
                          }
                        } else {
                          final m = await db.getPdfById(widget.ownerId);
                          if (m != null) {
                            final list = <int>[sel, ...m.recentColors.where((x) => x != sel)];
                            await db.upsertPdf(m.copyWith(lastOpened: m.lastOpened, lastPage: m.lastPage, recentColors: list.take(8).toList()));
                          }
                        }
                      } catch (_) {}
                      widget.onSelect(c);
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.onSurface.withAlpha((0.12 * 255).round())),
                      ),
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
