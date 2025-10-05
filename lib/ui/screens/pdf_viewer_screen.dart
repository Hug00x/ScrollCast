import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show MatrixUtils;

import '../widgets/text_note_bubble.dart';
import '../widgets/draggable_note_panel.dart';          // << NOVO
import '../../main.dart';
import '../../models/annotations.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/annotation_toolbar.dart';
import '../widgets/whatsapp_mic_button.dart';
import '../widgets/audio_pin_layer.dart';

class PdfViewerArgs {
  final String pdfId;
  final String name;
  final String path;
  const PdfViewerArgs({required this.pdfId, required this.name, required this.path});
}

class PdfViewerScreen extends StatefulWidget {
  static const route = '/pdf';
  final PdfViewerArgs args;
  const PdfViewerScreen({super.key, required this.args});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  int _pageCount = 1;
  int _pageIndex = 0;

  final _pageCache = <int, Uint8List>{};
  Uint8List? get _pageBytes => _pageCache[_pageIndex];

  final _strokes = <Stroke>[];
  final _undo = <Stroke>[];
  final _audioNotes = <AudioNote>[];
  final _textNotes = <TextNote>[];

  Size _imgSize = const Size(1, 1);

  StrokeMode _mode = StrokeMode.pen;
  double _width = 4;
  int _color = 0xFF00FF00;

  final _ivController = TransformationController();
  bool _canvasIgnore = false;
  double _currentScale = 1.0;

  bool _handMode = false;
  bool _loading = true;

  // estado do painel flutuante de notas
  int? _openedNoteIndex;
  final Map<int, Offset> _notePanelPos = {}; // posição por índice (sessão)

  @override
  void initState() {
    super.initState();
    _initDoc();
  }

  Future<void> _initDoc() async {
    setState(() => _loading = true);
    final pdf = ServiceLocator.instance.pdf;
    final count = await pdf.getPageCount(widget.args.path);
    setState(() => _pageCount = count);
    await _ensureRendered(_pageIndex);
    await _loadAnnotations(_pageIndex);
    setState(() => _loading = false);
  }

  Future<void> _ensureRendered(int i) async {
    if (_pageCache.containsKey(i)) return;
    final pdf = ServiceLocator.instance.pdf;
    final bytes = await pdf.renderPageAsImage(widget.args.path, i, targetWidth: 2400);
    _pageCache[i] = bytes;
  }

  Future<void> _loadAnnotations(int i) async {
    final db = ServiceLocator.instance.db;
    final ann = await db.getPageAnnotations(widget.args.pdfId, i);
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

    _ivController.value = Matrix4.identity();
    _currentScale = 1.0;
    _handMode = false;
    _canvasIgnore = false;
    _openedNoteIndex = null;
    _notePanelPos.clear();
  }

  Future<void> _savePage() async {
    await ServiceLocator.instance.db.savePageAnnotations(
      PageAnnotations(
        pdfId: widget.args.pdfId,
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
    await _ensureRendered(i);
    await _loadAnnotations(i);
    setState(() => _pageIndex = i);
  }

  void _onUndo() {
    if (_strokes.isEmpty) return;
    setState(() => _undo.add(_strokes.removeLast()));
  }

  void _onRedo() {
    if (_undo.isEmpty) return;
    setState(() => _strokes.add(_undo.removeLast()));
  }

  Future<void> _exportPdf() async {
    final all = await ServiceLocator.instance.db.getAllAnnotations(widget.args.pdfId);
    final dir = await ServiceLocator.instance.storage.exportedPdfDir();
    final out = await ServiceLocator.instance.storage.createUniqueFilePath(dir, extension: 'pdf');
    await ServiceLocator.instance.pdf.exportFlattened(
      originalPath: widget.args.path,
      annotationsByPage: all,
      outPath: out,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exportado para: $out')));
  }

  Offset _contentCenter(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return const Offset(0, 0);
    final size = box.size;
    final center = Offset(size.width / 2, size.height / 2);
    final inv = Matrix4.inverted(_ivController.value);
    return MatrixUtils.transformPoint(inv, center);
  }

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

  @override
  Widget build(BuildContext context) {
    if (_loading || _pageBytes == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final canPrev = _pageIndex > 0;
    final canNext = _pageIndex < _pageCount - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.args.name} (${_pageIndex + 1}/$_pageCount)'),
        actions: [
          IconButton(onPressed: _exportPdf, icon: const Icon(Icons.save_alt)),
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

            // Toggle Mão/Desenhar — AGORA AQUI EM BAIXO
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

            // Nova nota de texto
            IconButton.filledTonal(
              tooltip: 'Nova nota de texto',
              onPressed: () => _createTextNote(context),
              icon: const Icon(Icons.notes_rounded),
            ),

            const Spacer(),
            IconButton(
              onPressed: canNext ? () => _goTo(_pageIndex + 1) : null,
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Seguinte',
            ),
          ],
        ),
      ),

      body: Column(
        children: [
          // Barra de ferramentas (sem o toggle mão)
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
                            children: [
                              Center(child: Image.memory(_pageBytes!, gaplessPlayback: true)),

                              // medir a área útil para clamp dos pins
                              Positioned.fill(
                                child: LayoutBuilder(
                                  builder: (_, c2) {
                                    _imgSize = Size(c2.maxWidth, c2.maxHeight);
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ),

                              // Canvas
                              Positioned.fill(
                                child: IgnorePointer(
                                  ignoring: _handMode || _canvasIgnore,
                                  child: DrawingCanvas(
                                    key: ValueKey('canvas-$_pageIndex'),
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
                                      if (ignore != _canvasIgnore) setState(() => _canvasIgnore = ignore);
                                    },
                                  ),
                                ),
                              ),

                              // Pinos de áudio
                             // ...
Positioned.fill(
  child: AudioPinLayer(
    notes: _audioNotes,
    scale: _currentScale.clamp(0.6, 4.0),
    onMove: (idx, pos) async {
      setState(() => _audioNotes[idx] = _audioNotes[idx].copyWith(position: pos));
      await _savePage();
    },
    onDelete: (idx) async {
      setState(() => _audioNotes.removeAt(idx));
      await _savePage();
    },
    overlay: Overlay.of(context), // <- NOVO
  ),
),
// ...


                              // Pins de notas de texto (agora só o círculo)
                              ..._textNotes.indexed.map((entry) {
                                final idx = entry.$1;
                                final note = entry.$2;
                                return TextNoteBubble(
                                  key: ValueKey('txtpin-$idx-$_pageIndex'),
                                  note: note,
                                  canvasSize: _imgSize,
                                  onChanged: (updated) async {
                                    setState(() => _textNotes[idx] = updated);
                                    await _savePage();
                                  },
                                  onOpen: () {
                                    setState(() => _openedNoteIndex = idx);
                                  },
                                );
                              }),

                              // Painel flutuante quando uma nota está aberta
                              if (_openedNoteIndex != null) ...[
                                // Tap fora fecha
                                Positioned.fill(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _openedNoteIndex = null),
                                    child: const SizedBox.shrink(),
                                  ),
                                ),
                                DraggableNotePanel(
                                  key: ValueKey('panel-$_openedNoteIndex-$_pageIndex'),
                                  note: _textNotes[_openedNoteIndex!],
                                  initialPosition: _notePanelPos[_openedNoteIndex!] ??
                                      Offset(32, kToolbarHeight + 24),
                                  onPositionChanged: (pos) {
                                    _notePanelPos[_openedNoteIndex!] = pos;
                                  },
                                  onTextChanged: (txt) async {
                                    final i = _openedNoteIndex!;
                                    final n = _textNotes[i];
                                    setState(() => _textNotes[i] = TextNote(position: n.position, text: txt));
                                    await _savePage();
                                  },
                                  onDelete: () async {
                                    final i = _openedNoteIndex!;
                                    setState(() {
                                      _textNotes.removeAt(i);
                                      _openedNoteIndex = null;
                                    });
                                    await _savePage();
                                  },
                                  onClose: () => setState(() => _openedNoteIndex = null),
                                ),
                              ],
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
    );
  }
}
