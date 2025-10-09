import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show MatrixUtils;

import '../widgets/text_note_bubble.dart';
import '../widgets/draggable_note_panel.dart';
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
  double _eraserWidth = 18;

  final _ivController = TransformationController();
  bool _canvasIgnore = false;
  double _currentScale = 1.0;

  bool _handMode = false;
  bool _loading = true;

  // painel flutuante de notas
  int? _openedNoteIndex;
  final Map<int, Offset> _notePanelPos = {};

  // ⬇️ NOVO: chave e rect global da área do papel
  final GlobalKey _paperKey = GlobalKey();
  Rect? _paperRect; // em coordenadas globais (tela)

  // valores aproximados do painel (para clamp)
  static const Size _kNotePanelSize = Size(280, 200);

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

    // Atualiza rect do papel no próximo frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePaperRect());
  }

  // ⬇️ NOVO: calcula o rect global da área do papel
  void _updatePaperRect() {
    final ctx = _paperKey.currentContext;
    final overlay = Overlay.of(context);
    if (ctx == null || overlay == null) return;
    final rb = ctx.findRenderObject() as RenderBox?;
    if (rb == null) return;
    final topLeft = rb.localToGlobal(Offset.zero);
    final size = rb.size;
    setState(() {
      _paperRect = Rect.fromLTWH(topLeft.dx, topLeft.dy, size.width, size.height);
    });
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

  // ⬇️ NOVO: clamp posição de painel à caixa do papel
  Offset _clampToPaper(Offset desired, Size widgetSize) {
    final r = _paperRect;
    if (r == null) return desired;
    final pad = 8.0;
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
                            // atualiza também o rect do papel (pode mudar com layout)
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
                                key: _paperKey, // ⬅️ mede a área do papel
                                children: [
                                  Center(child: Image.memory(_pageBytes!, gaplessPlayback: true)),

                                  Positioned.fill(
                                    child: LayoutBuilder(
                                      builder: (_, c2) {
                                        _imgSize = Size(c2.maxWidth, c2.maxHeight);
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                  ),

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
                                        eraserWidthPreview: _eraserWidth,
                                        onStrokesChanged: () async {
                                          await _savePage();
                                        },
                                      ),
                                    ),
                                  ),

                                  // Pinos de áudio — HUD confinado ao papel
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
                                      overlay: Overlay.of(context),
                                      allowedBounds: _paperRect, // ⬅️ NOVO
                                    ),
                                  ),

                                  // Pins de notas de texto
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
                                        setState(() {
                                          _openedNoteIndex = idx;
                                          _notePanelPos.putIfAbsent(
                                            idx,
                                            () {
                                              // posição inicial “dentro do papel”
                                              final r = _paperRect;
                                              if (r == null) return const Offset(24, kToolbarHeight + 24);
                                              final start = Offset(r.left + 24, r.top + 24);
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
            ],
          ),

          // Painel flutuante (fora do InteractiveViewer), mas limitado ao papel
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
                final current = _notePanelPos[_openedNoteIndex!] ?? const Offset(24, kToolbarHeight + 24);
                final clamped = _clampToPaper(current, _kNotePanelSize); // ⬅️ aplica limites
                return Positioned(
                  left: clamped.dx,
                  top: clamped.dy,
                  child: DraggableNotePanel(
                    key: ValueKey('panel-$_openedNoteIndex-$_pageIndex'),
                    note: _textNotes[_openedNoteIndex!],
                    initialPosition: clamped,
                    onPositionChanged: (pos) {
                      // sempre clamp ao mover
                      _notePanelPos[_openedNoteIndex!] = _clampToPaper(pos, _kNotePanelSize);
                      setState(() {});
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
