import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';
// MatrixUtils is available through material.dart; explicit import removed to silence analyzer
import '../../main.dart';
import '../../models/annotations.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/annotation_toolbar.dart';
import '../widgets/whatsapp_mic_button.dart';
import '../widgets/audio_pin_layer.dart';
import '../widgets/text_note_bubble.dart';
import '../widgets/image_note_widget.dart';

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
  int _pageCount = 1;
  int _pageIndex = 0;

  final _strokes = <Stroke>[];
  final List<List<Stroke>> _undoStack = [];
  final List<List<Stroke>> _redoStack = [];
  final _audioNotes = <AudioNote>[];
  final _textNotes = <TextNote>[];
  final _imageNotes = <ImageNote>[];

  Size _paperSize = const Size(1, 1);

  StrokeMode _mode = StrokeMode.pen;
  double _width = 4;
  int _color = 0xFF00FF00;
  double _eraserWidth = 18;

  final _ivController = TransformationController();
  bool _canvasIgnore = false;
  double _currentScale = 1.0;
  bool _handMode = false;

  // ===== Stylus =====
  bool _stylusDown = false;
  bool _stylusEverSeen = false;

  // painel inferior de nota
  int? _openedNoteIndex;
  final _noteEditor = TextEditingController();

  // limites para o HUD de áudio
  final GlobalKey _paperKey = GlobalKey();
  Rect? _paperRect;

  String get _nbId => 'NB_${widget.args.notebookId}';

  @override
  void initState() {
    super.initState();
    _initNotebook();
  }

  @override
  void dispose() {
    _noteEditor.dispose();
    super.dispose();
  }

  Future<void> _initNotebook() async {
    final existing = await ServiceLocator.instance.db.getAllAnnotations(_nbId);
    if (existing.isNotEmpty) {
      _pageCount = (existing.map((e) => e.pageIndex).fold<int>(0, (m, i) => i > m ? i : m)) + 1;
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
  _undoStack.clear();
  _redoStack.clear();
    _audioNotes
      ..clear()
      ..addAll(ann?.audioNotes ?? const []);
    _textNotes
      ..clear()
      ..addAll(ann?.textNotes ?? const []);
    _imageNotes
      ..clear()
      ..addAll(ann?.imageNotes ?? const []);

    // reset enquadramento/UI mas NÃO mexer no _stylusEverSeen
    _ivController.value = Matrix4.identity();
    _currentScale = 1.0;
    _handMode = false;
    _canvasIgnore = false;

    _openedNoteIndex = null;
    _noteEditor.clear();

    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePaperRect());
  }

  Future<void> _savePage() async {
    await ServiceLocator.instance.db.savePageAnnotations(
      PageAnnotations(
        pdfId: _nbId,
        pageIndex: _pageIndex,
        strokes: List.of(_strokes),
        audioNotes: List.of(_audioNotes),
        textNotes: List.of(_textNotes),
        imageNotes: List.of(_imageNotes),
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
    setState(() => _pageCount += 1);
    await _goTo(_pageCount - 1);
  }

  Future<void> _removeCurrentPage() async {
    if (_pageCount <= 1) return;
    await ServiceLocator.instance.db.deleteAnnotations(_nbId, pageIndex: _pageIndex);
    final nextIndex = _pageIndex.clamp(0, _pageCount - 2);
    setState(() => _pageCount -= 1);
    await _goTo(nextIndex);
  }

  // undo/redo
  Future<void> _onUndo() async {
    if (_undoStack.isEmpty) return;
    // push current state to redo
    _redoStack.add(_cloneStrokes(_strokes));
    // restore previous
    final prev = _undoStack.removeLast();
    setState(() {
      _strokes
        ..clear()
        ..addAll(prev.map((s) => _cloneStroke(s)));
    });
    await _savePage();
  }

  Future<void> _onRedo() async {
    if (_redoStack.isEmpty) return;
    // push current state to undo
    _undoStack.add(_cloneStrokes(_strokes));
    final next = _redoStack.removeLast();
    setState(() {
      _strokes
        ..clear()
        ..addAll(next.map((s) => _cloneStroke(s)));
    });
    await _savePage();
  }

  List<Stroke> _cloneStrokes(List<Stroke> src) => src.map((s) => _cloneStroke(s)).toList();

  Stroke _cloneStroke(Stroke s) => Stroke(points: List.of(s.points), width: s.width, color: s.color, mode: s.mode);

  void _pushUndoSnapshot() {
    _undoStack.add(_cloneStrokes(_strokes));
    // keep redo cleared when user makes a new action
    _redoStack.clear();
  }

  // notas
  Future<void> _createTextNote() async {
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
  // the dialog awaits; guard against using the State.context if the widget was disposed
  if (!mounted) return;

  final center = _contentCenter(context);
  setState(() => _textNotes.add(TextNote(position: center, text: text)));
    await _savePage();
  }

  void _openNoteSheet(int index) {
    _openedNoteIndex = index;
    _noteEditor.text = _textNotes[index].text;
    setState(() {});
  }

  void _closeNoteSheet() {
    _openedNoteIndex = null;
    _noteEditor.clear();
    setState(() {});
  }

  Future<void> _deleteOpenedNote() async {
    if (_openedNoteIndex == null) return;
    final i = _openedNoteIndex!;
    setState(() {
      _textNotes.removeAt(i);
      _openedNoteIndex = null;
    });
    await _savePage();
  }

  Future<void> _applyNoteText(String v) async {
    if (_openedNoteIndex == null) return;
    final i = _openedNoteIndex!;
    final n = _textNotes[i];
    setState(() => _textNotes[i] = TextNote(position: n.position, text: v.trim()));
    await _savePage();
  }

  Future<void> _importImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;

    final src = x.path;
    final storage = ServiceLocator.instance.storage;
    final root = await storage.appRoot();
    final imagesDir = p.join(root, 'images');
    // ensure dir exists
    try {
      final d = Directory(imagesDir);
      if (!await d.exists()) await d.create(recursive: true);
    } catch (_) {}
    final ext = p.extension(src).replaceFirst('.', '');
    final dest = await storage.createUniqueFilePath(imagesDir, extension: ext.isEmpty ? 'jpg' : ext);
    await storage.copyFile(src, dest);

    if (!mounted) return;
    final center = _contentCenter(context);
    final defaultSize = math.min(_paperSize.width, _paperSize.height) * 0.3;
    setState(() => _imageNotes.add(ImageNote(position: center, filePath: dest, width: defaultSize, height: defaultSize)));
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

  void _updatePaperRect() {
    final ctx = _paperKey.currentContext;
    final rb = ctx?.findRenderObject() as RenderBox?;
    if (rb == null) return;
    final topLeft = rb.localToGlobal(Offset.zero);
    final size = rb.size;
    setState(() {
      _paperRect = Rect.fromLTWH(topLeft.dx, topLeft.dy, size.width, size.height);
    });
  }

  @override
  Widget build(BuildContext context) {
    final canPrev = _pageIndex > 0;
    final canNext = _pageIndex < _pageCount - 1;
    final sheetOpen = _openedNoteIndex != null;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.args.name} (${_pageIndex + 1}/$_pageCount)'),
        actions: [
          IconButton(
            tooltip: 'Importar imagem',
            onPressed: _importImage,
            icon: const Icon(Icons.image_outlined),
          ),
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
            IconButton(
              onPressed: canPrev ? () => _goTo(_pageIndex - 1) : null,
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Anterior',
            ),
            Tooltip(
              message: _stylusEverSeen
                  ? 'Caneta detetada — os dedos servem para arrastar/zoom'
                  : (_handMode ? 'Modo mão (arrastar) ativo' : 'Ativar modo mão'),
              child: IconButton.filledTonal(
                onPressed: _stylusEverSeen
                    ? null
                    : () {
                        setState(() {
                          _handMode = !_handMode;
                          _canvasIgnore = _handMode;
                        });
                      },
                icon: Icon(_handMode ? Icons.pan_tool_alt : Icons.brush),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Nova nota de texto',
              onPressed: _createTextNote,
              icon: const Icon(Icons.notes_rounded),
            ),
            // moved 'Importar imagem' to AppBar to avoid overlap with audio FAB on small screens
            const Spacer(),
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

      body: Stack(
        children: [
          Column(
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
                  canUndo: _undoStack.isNotEmpty,
                  canRedo: _redoStack.isNotEmpty,
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
                          // quando a caneta está a tocar, desativar pan para evitar que a caneta arraste
                          panEnabled: !_stylusDown && (_stylusEverSeen ? true : _handMode),
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
                                key: _paperKey,
                                children: [
                                  // “folha” branca
                                  Center(
                                    child: LayoutBuilder(
                                      builder: (_, c2) {
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
                                  // Canvas — caneta desenha; dedos não
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      ignoring: (!_stylusDown) && (_handMode || _canvasIgnore),
                                      child: DrawingCanvas(
                                        key: ValueKey('nb-canvas-$_pageIndex'),
                                        strokes: _strokes,
                                        mode: _mode,
                                        strokeWidth: _width,
                                        strokeColor: _color,
                                        stylusOnly: _stylusEverSeen,
                                        onStrokeEnd: (s) async {
                                          _pushUndoSnapshot();
                                          setState(() => _strokes.add(s));
                                          await _savePage();
                                        },
                                        onPointerCountChanged: (count) {
                                          final ignore = (_handMode || count >= 2);
                                          if (ignore != _canvasIgnore) {
                                            setState(() => _canvasIgnore = ignore);
                                          }
                                        },
                                        eraserWidthPreview: _eraserWidth,
                                        onStrokesChanged: () async {
                                          await _savePage();
                                        },
                                        onBeforeErase: () => _pushUndoSnapshot(),
                                        onStylusContact: (down) {
                                          if (down && !_stylusEverSeen) {
                                            if (mounted) setState(() => _stylusEverSeen = true);
                                          }
                                          if (down != _stylusDown) {
                                            if (mounted) setState(() => _stylusDown = down);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                  // áudio
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
                                  // pinos de notas
                                  // imagens
                                  ..._imageNotes.indexed.map((entry) {
                                    final idx = entry.$1;
                                    final note = entry.$2;
                                    return ImageNoteWidget(
                                      key: ValueKey('nb-img-$idx-$_pageIndex'),
                                      note: note,
                                      canvasSize: _paperSize,
                                      onChanged: (updated) async {
                                        setState(() => _imageNotes[idx] = updated);
                                        await _savePage();
                                      },
                                      onDelete: () async {
                                        setState(() => _imageNotes.removeAt(idx));
                                        await _savePage();
                                      },
                                    );
                                  }),

                                  // pinos de notas (texto)
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
                                      onOpen: () => _openNoteSheet(idx),
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
            ],
          ),

          _NoteBottomSheet(
            visible: sheetOpen,
            controller: _noteEditor,
            onChanged: _applyNoteText,
            onClose: _closeNoteSheet,
            onDelete: _deleteOpenedNote,
            bottomBarHeight: 64,
          ),
        ],
      ),
    );
  }
}

/// Reutilizamos o mesmo widget do ficheiro do PDF
class _NoteBottomSheet extends StatelessWidget {
  const _NoteBottomSheet({
    required this.visible,
    required this.controller,
    required this.onChanged,
    required this.onClose,
    required this.onDelete,
    required this.bottomBarHeight,
  });

  final bool visible;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final Future<void> Function() onDelete;
  final double bottomBarHeight;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.bottom;
    final base = Theme.of(context).colorScheme;
    const height = 140.0;

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(0, 1.2),
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomBarHeight + pad + 8, left: 8, right: 8),
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(16),
            color: base.surface,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sticky_note_2_outlined, size: 18),
                        const SizedBox(width: 6),
                        const Expanded(child: Text('Nota', style: TextStyle(fontWeight: FontWeight.w600))),
                        IconButton(
                          tooltip: 'Apagar',
                          onPressed: () async => await onDelete(),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                        IconButton(
                          tooltip: 'Fechar',
                          onPressed: onClose,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        maxLines: null,
                        onChanged: onChanged,
                        decoration: const InputDecoration(
                          hintText: 'Escreve a tua nota…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
