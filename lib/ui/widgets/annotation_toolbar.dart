import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/services.dart';
import '../../models/annotations.dart';
import '../../main.dart';

/*
  annotation_toolbar.dart

  Propósito geral:
  - Este ficheiro fornece a toolbar de anotação usada no visualizador de PDFs/notebooks.
  - Principais responsabilidades:
    - Escolha de modo de traço (caneta / borracha).
    - Seleção de cor (paleta rápida, picker detalhado e editor HEX).
    - Controlo de largura do traço e largura da borracha.
    - Ações de desfazer/refazer.
    - Persistência das cores recentes por documento (PDF ou notebook) através do DatabaseService.

  Organização do ficheiro:
  - A toolbar é um widget stateless com callbacks para todas as ações para manter
    a lógica de desenho fora do widget.
  - Quando uma cor é escolhida, opcionalmente atualizamos o modelo do documento
    (pdf ou notebook) para armazenar a lista `recentColors` — até 8 valores.
  - O editor HEX abre um bottom sheet para inserir manualmente valores RRGGBB.
*/

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final upper = newValue.text.toUpperCase();
    return TextEditingValue(text: upper, selection: newValue.selection);
  }
}

// Formatter simples que força entrada em maiúsculas (usado no editor HEX)

// Widget principal da toolbar de anotação.
// - Recebe o estado atual (modo, cor, larguras) e expõe callbacks para que a
//   lógica de desenho possa reagir às alterações.
// - Tem integração com o DatabaseService para armazenar cores recentes
//   por documento (quando `ownerId` for fornecido).
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

  final int color;
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

  // Abre um diálogo para escolher uma cor com o ColorPicker.
  // Fluxo resumido:
  // 1) Inicializa `temp` com a cor atual.
  // 2) Mostra um AlertDialog com um `ColorPicker` e uma opção para abrir
  //    o editor HEX.
  // 3) Se o utilizador confirmar, chama onColorChanged com o ARGB selecionado.
  // 4) Se `ownerId` estiver definido, insere a cor no histórico `recentColors`
  //    do documento (notebook/pdf) e guarda (até 8 entradas).
  Future<void> _pickColor(BuildContext context) async {
    Color temp = Color(color);
    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        String colorToHex(Color c) {
          final r = ((c.r * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0');
          final g = ((c.g * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0');
          final b = ((c.b * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0');
          return (r + g + b).toUpperCase();
        }

  controller.text = colorToHex(temp);
  controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));

  // StatefulBuilder permite alterar `temp` dentro do diálogo sem
  // reconstruir todo o widget pai.
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
          // Abre um bottom sheet para o utilizador inserir manualmente um código HEX
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

          // Diálogo principal de escolha de cor.
          // Contém o picker visual e um botão que abre o editor HEX.
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
                    labelTypes: const [],
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
  // Se o utilizador escolheu uma cor (clicou OK), atualizamos o callback
  // e guardamos a cor nas `recentColors` do documento.
  if (picked != null) {
      final int argb = picked.toARGB32();
      onColorChanged(argb);
      if (ownerId != null) {
        try {
          final db = ServiceLocator.instance.db;
          if (ownerIsNotebook) {
            final model = await db.getNotebookById(ownerId!);
            if (model != null) {
              final list = <int>[argb, ...model.recentColors.where((c) => c != argb)];
              final trimmed = list.take(8).toList();
              await db.upsertNotebook(model.copyWith(lastOpened: model.lastOpened, lastPage: model.lastPage, recentColors: trimmed));
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
              color: scheme.surface.withAlpha((0.6 * 255).round()),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // Linha superior: botões de modo (caneta/borracha) + undo/redo
            // Utilizamos um SingleChildScrollView horizontal para permitir overflow suave em ecrãs pequenos.
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
          //Linha inferior: paleta de cores + slider de largura
            _ColorPaletteWithPicker(
              selected: color,
              onChanged: (c) {
                if (!enabled) return;
                onColorChanged(c);

                if (ownerId != null) {
                  () async {
                    try {
                      final db = ServiceLocator.instance.db;
                      if (ownerIsNotebook) {
                        final model = await db.getNotebookById(ownerId!);
                        if (model != null) {
                          final list = <int>[c, ...model.recentColors.where((x) => x != c)];
                          final trimmed = list.take(8).toList();
                          await db.upsertNotebook(model.copyWith(lastOpened: model.lastOpened, lastPage: model.lastPage, recentColors: trimmed));
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

                showModalBottomSheet<void>(
                  context: context,
                  builder: (ctx) => _RecentColorsSheet(ownerId: ownerId!, ownerIsNotebook: ownerIsNotebook, onSelect: (col) { if (enabled) onColorChanged(col); }),
                );
              },
              enabled: enabled,
            ),

            const SizedBox(height: 4),

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
  // Botão de modo (caneta / borracha) usado na barra superior.
  // - Mostra um ícone e um label curto.
  // - Quando `selected` é true aplica uma aparência destacada (border e cor primaria).
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
    // O efeito muda quando `selected` para sinalizar o estado ativo.
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

    // A paleta ocupa uma altura fixa e apresenta os círculos de cor
    // horizontalmente. Usamos ListView.separated para espaçamento consistente.
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(right: 4),
  itemBuilder: (_, i) {
          // O último índice depois da paleta padrão: botão para abrir o picker
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
          // Botão para abrir o sheet de cores recentes
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
        itemCount: _colors.length + 2, 
      ),
    );
  }
}
//Bottom sheet que mostra as cores recentes do documento (notebook/pdf)
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
  //Carrega as cores recentes do documento (notebook/pdf) do DB
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
  // Ao limpar, gravamos o modelo com recentColors vazio (mantemos lastOpened/lastPage)
  if (m != null) await db.upsertNotebook(m.copyWith(lastOpened: m.lastOpened, lastPage: m.lastPage, recentColors: []));
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
        
                IconButton(
                  tooltip: 'Limpar histórico',
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Limpar histórico'),
                        content: const Text('Tens a certeza que queres apagar o histórico?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Apagar')),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await _clearAll();
                    }
                  },
                  icon: const Icon(Icons.delete_sweep_rounded),
                ),
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
                      final sel = c;
                      final nav = Navigator.of(context);
                      try {
                        final db = ServiceLocator.instance.db;
                        if (widget.ownerIsNotebook) {
                          final m = await db.getNotebookById(widget.ownerId);
                          if (m != null) {
                            final list = <int>[sel, ...m.recentColors.where((x) => x != sel)];
                            await db.upsertNotebook(m.copyWith(lastOpened: m.lastOpened, lastPage: m.lastPage, recentColors: list.take(8).toList()));
                          }
                        } else {
                          final m = await db.getPdfById(widget.ownerId);
                          if (m != null) {
                            final list = <int>[sel, ...m.recentColors.where((x) => x != sel)];
                            await db.upsertPdf(m.copyWith(lastOpened: m.lastOpened, lastPage: m.lastPage, recentColors: list.take(8).toList()));
                          }
                        }
                      } catch (_) {}
                      if (!mounted) return;
                      widget.onSelect(c);
                      nav.pop();
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
