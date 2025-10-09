import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show MatrixUtils;

import '../../main.dart';
import '../../models/annotations.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/annotation_toolbar.dart';
import '../widgets/whatsapp_mic_button.dart';
import '../widgets/audio_pin_layer.dart';
import '../widgets/text_note_bubble.dart';
import '../widgets/draggable_note_panel.dart';

/// Args para abrir um caderno em branco
class NotebookViewerArgs {
  final String notebookId;
  final String name;
  const NotebookViewerArgs({required this.notebookId, required this.name});
}

class NotebookViewerScreen extends StatefulWidget {
  static const route = '/notebook';
  final NotebookViewerArgs args;
  const NotebookViewerScreen({super.key, required this.args});

  @override
  State<NotebookViewerScreen> createState() => _NotebookViewerScreenState();
}

class _NotebookViewerScreenState extends State<NotebookViewerScreen> {
  // páginas
  int _pageCount = 1;
  int _pageIndex = 0;

  // dados
  final _strokes = <Stroke>[];
  final _undo = <Stroke>[];
  final _audioNotes = <AudioNote>[];
  final _textNotes = <TextNote>[];

  Size _paperSize = const Size(1, 1);

  // desenho
  StrokeMode _mode = StrokeMode.pen;
  double _width = 4;
  int _color = 0xFF00FF00;
  double _eraserWidth = 18;

  // zoom/pan
  final _ivController = TransformationController();
  bool _canvasIgnore = false;
  double _currentScale = 1.0;
  bool _handMode = false;

  // painel de nota de texto
  int? _openedNoteIndex;
  final Map<int, Offset> _notePanelPos = {}; // posição do painel por índice

  // limites (para prender HUDs/paineis ao “papel”)
  final GlobalKey _paperKey = GlobalKey();
  Rect? _paperRect;
  static const Size _kNotePanelSize = Size(280, 200);

  String get _nbId => 'NB_${widget.args.notebookId}'; // reuse do storage de anotações

  @override
  void initState() {
    super.initState();
    _initNotebook();
  }

  Future<void> _initNotebook() async {
    // Descobre páginas que já existem (persistidas)
    final existing = await ServiceLocator.instance.db.getAllAnnotations(_nbId);
    if (existing.isNotEmpty) {
      _pageCount =
          (existing.map((e) => e.pageIndex).fold<int>(0, (m, i) => i > m ? i : m)) +
              1;
    } else {
      _pageCount = 1;
    }
    await _loadPage(_pageIndex);
    setState(() {});
  }

  Future<void> _loadPage(int i) async {
    final db = ServiceLocator.instance.db;
    final ann = await db.getPageAnnotations(_nbId, i);
    _strokes
      ..clear()
      ..addAll(ann?.strokes ?? const []);
    _undo.clear();
    _audioNotes
      ..clear()
      ..addAll(ann?.audioNotes ?? const []);
    _textNotes
      ..clear()
      ..addAll(ann?.textNotes ?? const []);

    // reset de estado de interação
    _ivController.value = Matrix4.identity();
    _currentScale = 1.0;
    _handMode = false;
    _canvasIgnore = false;
    _openedNoteIndex = null;
    _notePanelPos.clear();

    // mede limites do papel no próximo frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePaperRect());
  }

  Future<void> _savePage() async {
    await ServiceLocator.instance.db.savePageAnnotations(
      PageAnnotations(
        pdfId: _nbId, // <— reaproveitado
        pageIndex: _pageIndex,
        strokes: List.of(_strokes),
        audioNotes: List.of(_audioNotes),
        textNotes: List.of(_textNotes),
      ),
    );
  }

  Future<void> _goTo(int i) async {
    if (i < 0 || i >= _pageCount || i == _pageIndex) return;
    await _savePage();
    await _loadPage(i);
    setState(() => _pageIndex = i);
  }

  // páginas
  Future<void> _addPage() async {
    await _savePage();
    setState(() {
      _pageCount += 1;
    });
    await _goTo(_pageCount - 1);
  }

  Future<void> _removeCurrentPage() async {
    if (_pageCount <= 1) return;
    // apaga anotações desta página
    await ServiceLocator.instance.db.deleteAnnotations(_nbId, pageIndex: _pageIndex);

    // “encolhe” contador e ajusta índice
    final nextIndex = _pageIndex.clamp(0, _pageCount - 2);
    setState(() => _pageCount -= 1);
    await _goTo(nextIndex);
  }

  // undo/redo
  Future<void> _onUndo() async {
    if (_strokes.isEmpty) return;
    setState(() => _undo.add(_strokes.removeLast()));
    await _savePage();
  }

  Future<void> _onRedo() async {
    if (_undo.isEmpty) return;
    setState(() => _strokes.add(_undo.removeLast()));
    await _savePage();
  }

  // notas de texto
  Future<void> _createTextNote(BuildContext context) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova nota'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Escreve a tua nota…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Adicionar')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;

    final center = _contentCenter(context);
    setState(() => _textNotes.add(TextNote(position: center, text: text)));
    await _savePage();
  }

  Offset _contentCenter(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return const Offset(0, 0);
    final size = box.size;
    final center = Offset(size.width / 2, size.height / 2);
    final inv = Matrix4.inverted(_ivController.value);
    return MatrixUtils.transformPoint(inv, center);
  }

  // limites do papel (global)
  void _updatePaperRect() {
    final ctx = _paperKey.currentContext;
    if (ctx == null) return;
    final rb = ctx.findRenderObject() as RenderBox?;
    if (rb == null) return;
    final topLeft = rb.localToGlobal(Offset.zero);
    final size = rb.size;
    setState(() {
      _paperRect = Rect.fromLTWH(topLeft.dx, topLeft.dy, size.width, size.height);
    });
  }

  // clamp de paineis ao papel
  Offset _clampToPaper(Offset desired, Size widgetSize) {
    final r = _paperRect;
    if (r == null) return desired;
    const pad = 8.0;
    final minX = r.left + pad;
    final maxX = r.right - pad - widgetSize.width;
    final minY = r.top + pad;
    final maxY = r.bottom - pad - widgetSize.height;
    return Offset(
      desired.dx.clamp(minX, maxX).toDouble(),
      desired.dy.clamp(minY, maxY).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPrev = _pageIndex > 0;
    final canNext = _pageIndex < _pageCount - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.args.name} (${_pageIndex + 1}/$_pageCount)'),
        actions: [
          IconButton(
            tooltip: 'Repor enquadramento',
            onPressed: () => setState(() => _ivController.value = Matrix4.identity()),
            icon: const Icon(Icons.center_focus_strong),
          ),
        ],
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Builder(
        builder: (ctx) => WhatsAppMicButton(
          provideDirPath: () async => ServiceLocator.instance.storage.audioDir(),
          onSaved: (path, durMs) async {
            final center = _contentCenter(ctx);
            setState(() => _audioNotes.add(AudioNote(position: center, filePath: path, durationMs: durMs)));
            await _savePage();
          },
        ),
      ),

bottomNavigationBar: BottomAppBar(
  shape: const CircularNotchedRectangle(),
  notchMargin: 10,
  height: 64,
  child: Row(
    children: [
      // ← esquerda
      IconButton(
        onPressed: canPrev ? () => _goTo(_pageIndex - 1) : null,
        icon: const Icon(Icons.chevron_left),
        tooltip: 'Anterior',
      ),

      // toggle mão/desenho (fica na esquerda)
      Tooltip(
        message: _handMode ? 'Modo mão (arrastar) ativo' : 'Ativar modo mão',
        child: IconButton.filledTonal(
          onPressed: () {
            setState(() {
              _handMode = !_handMode;
              _canvasIgnore = _handMode;
            });
          },
          icon: Icon(_handMode ? Icons.pan_tool_alt : Icons.brush),
        ),
      ),

      // nova nota (também na esquerda)
      IconButton.filledTonal(
        tooltip: 'Nova nota de texto',
        onPressed: () => _createTextNote(context),
        icon: const Icon(Icons.notes_rounded),
      ),

      const Spacer(),

      // → direita: gerir páginas
      IconButton(
        tooltip: 'Remover página',
        onPressed: _pageCount > 1 ? _removeCurrentPage : null,
        icon: const Icon(Icons.delete_outline_rounded),
      ),
      IconButton(
        tooltip: 'Adicionar página',
        onPressed: _addPage,
        icon: const Icon(Icons.note_add_rounded),
      ),

      IconButton(
        onPressed: canNext ? () => _goTo(_pageIndex + 1) : null,
        icon: const Icon(Icons.chevron_right),
        tooltip: 'Seguinte',
      ),
    ],
  ),
),

      // Papel com ZOOM (InteractiveViewer) + tudo preso à área do papel
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 4, top: 4, bottom: 2),
            child: AnnotationToolbar(
              mode: _mode,
              onModeChanged: (m) => setState(() => _mode = m),
              width: _width,
              onWidthChanged: (w) => setState(() => _width = w),
              color: _color,
              onColorChanged: (c) => setState(() => _color = c),
              onUndo: _onUndo,
              onRedo: _onRedo,
              eraserWidth: _eraserWidth,
              onEraserWidthChanged: (v) => setState(() => _eraserWidth = v),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return InteractiveViewer(
                      transformationController: _ivController,
                      panEnabled: _handMode,
                      minScale: 1.0,
                      maxScale: 5.0,
                      boundaryMargin: EdgeInsets.zero,
                      clipBehavior: Clip.hardEdge,
                      scaleEnabled: true,
                      onInteractionUpdate: (_) {
                        _currentScale = _ivController.value.getMaxScaleOnAxis();
                        setState(() {});
                        WidgetsBinding.instance.addPostFrameCallback((_) => _updatePaperRect());
                      },
                      child: FittedBox(
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth,
                            maxHeight: constraints.maxHeight,
                          ),
                          child: Stack(
                            key: _paperKey, // mede a área do “papel”
                            children: [
                              // “Papel” branco com sombra suave
                              Center(
                                child: LayoutBuilder(
                                  builder: (_, c2) {
                                    // ocupa a área disponível — o DrawingCanvas usa estes limites
                                    _paperSize = Size(c2.maxWidth, c2.maxHeight);
                                    return Container(
                                      width: c2.maxWidth,
                                      height: c2.maxHeight,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x22000000),
                                            blurRadius: 12,
                                            offset: Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),

                              // Canvas de desenho
                              Positioned.fill(
                                child: IgnorePointer(
                                  ignoring: _handMode || _canvasIgnore,
                                  child: DrawingCanvas(
                                    key: ValueKey('nb-canvas-$_pageIndex'),
                                    strokes: _strokes,
                                    mode: _mode,
                                    strokeWidth: _width,
                                    strokeColor: _color,
                                    onStrokeEnd: (s) async {
                                      setState(() => _strokes.add(s));
                                      await _savePage();
                                    },
                                    onPointerCountChanged: (count) {
                                      final ignore = _handMode || count >= 2;
                                      if (ignore != _canvasIgnore) {
                                        setState(() => _canvasIgnore = ignore);
                                      }
                                    },
                                    eraserWidthPreview: _eraserWidth,
                                    onStrokesChanged: () async {
                                      await _savePage();
                                    },
                                  ),
                                ),
                              ),

                              // Pinos de áudio (HUD preso à área do papel)
                              Positioned.fill(
                                child: AudioPinLayer(
                                  notes: _audioNotes,
                                  scale: _currentScale.clamp(0.6, 4.0),
                                  onMove: (idx, pos) async {
                                    setState(() => _audioNotes[idx] =
                                        _audioNotes[idx].copyWith(position: pos));
                                    await _savePage();
                                  },
                                  onDelete: (idx) async {
                                    setState(() => _audioNotes.removeAt(idx));
                                    await _savePage();
                                  },
                                  overlay: Overlay.of(context),
                                  allowedBounds: _paperRect,
                                ),
                              ),

                              // Pinos das notas de texto (apenas o “pin”)
                              ..._textNotes.indexed.map((entry) {
                                final idx = entry.$1;
                                final note = entry.$2;
                                return TextNoteBubble(
                                  key: ValueKey('nb-txtpin-$idx-$_pageIndex'),
                                  note: note,
                                  canvasSize: _paperSize,
                                  onChanged: (updated) async {
                                    setState(() => _textNotes[idx] = updated);
                                    await _savePage();
                                  },
                                  onOpen: () {
                                    setState(() {
                                      _openedNoteIndex = idx;
                                      _notePanelPos.putIfAbsent(
                                        idx,
                                        () {
                                          final r = _paperRect;
                                          if (r == null) {
                                            return const Offset(24, kToolbarHeight + 24);
                                          }
                                          final start =
                                              Offset(r.left + 24, r.top + 24);
                                          return _clampToPaper(start, _kNotePanelSize);
                                        },
                                      );
                                    });
                                  },
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // Painel flutuante da nota (fora do zoom) mas confinado ao papel
          if (_openedNoteIndex != null) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => setState(() => _openedNoteIndex = null),
                child: const SizedBox.shrink(),
              ),
            ),
            Builder(
              builder: (_) {
                final current =
                    _notePanelPos[_openedNoteIndex!] ?? const Offset(24, kToolbarHeight + 24);
                final clamped = _clampToPaper(current, _kNotePanelSize);
                return Positioned(
                  left: clamped.dx,
                  top: clamped.dy,
                  child: DraggableNotePanel(
                    key: ValueKey('nb-panel-$_openedNoteIndex-$_pageIndex'),
                    note: _textNotes[_openedNoteIndex!],
                    initialPosition: clamped,
                    onPositionChanged: (pos) {
                      _notePanelPos[_openedNoteIndex!] =
                          _clampToPaper(pos, _kNotePanelSize);
                      setState(() {});
                    },
                    onTextChanged: (txt) async {
                      final i = _openedNoteIndex!;
                      final n = _textNotes[i];
                      setState(() => _textNotes[i] =
                          TextNote(position: n.position, text: txt));
                      await _savePage();
                    },
                    onDelete: () async {
                      final i = _openedNoteIndex!;
                      setState(() {
                        _textNotes.removeAt(i);
                        _notePanelPos.remove(i);
                        _openedNoteIndex = null;
                      });
                      await _savePage();
                    },
                    onClose: () => setState(() => _openedNoteIndex = null),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
