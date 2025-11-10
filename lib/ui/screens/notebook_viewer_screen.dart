import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';
import '../../main.dart';
import '../../models/annotations.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/annotation_toolbar.dart';
import '../widgets/whatsapp_mic_button.dart';
import '../widgets/audio_pin_layer.dart';
import '../widgets/text_note_bubble.dart';
import '../widgets/image_note_widget.dart';

/*
  Notebook viewer screen

  Propósito geral:
  - Fornece a interface para visualizar e editar páginas de um caderno interno (notebook) do ScrollCast.
  - Gere a navegação entre páginas, carregamento/gravação de anotações (strokes, notas de texto, áudio e imagens),
    além das ações do utilizador como adicionar/remover páginas, desfazer/refazer, e importar imagens.
  - Persiste metadados do caderno (última página aberta, contagem de páginas) através do serviço de base de dados.

  Organização do ficheiro:
  - `NotebookViewerArgs`: argumentos simples para abrir o ecrã.
  - `NotebookViewerScreen`: widget de estado que controla todo o fluxo de leitura/gravação de anotações e UI.
  - `_NoteBottomSheet`: componente auxiliar para edição rápida de notas de texto.
*/

// Contém o id do caderno e o nome apresentado na AppBar.
class NotebookViewerArgs {
  final String notebookId;
  final String name;
  const NotebookViewerArgs({required this.notebookId, required this.name});
}

// Tela principal do visualizador de cadernos.
// Gerencia estado local da edição (páginas, anotações, notas multimédia) e é responsável pelas
// chamadas ao serviço de persistência quando a página muda ou quando o ecrã é fechado.
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
  int _color = 0xFF000000;
  double _eraserWidth = 18;

  final _ivController = TransformationController();
  bool _canvasIgnore = false;
  double _currentScale = 1.0;
  bool _handMode = false;

  bool _stylusDown = false;
  bool _stylusEverSeen = false;

  int? _openedNoteIndex;
  final _noteEditor = TextEditingController();

  final GlobalKey _paperKey = GlobalKey();
  Rect? _paperRect;

  String get _nbId => 'NB_${widget.args.notebookId}';

  // Inicialização do State: chama o carregamento assíncrono do caderno.
  @override
  void initState() {
    super.initState();
    _initNotebook();
  }

  // Limpeza de recursos: descarta o controller do editor e grava metadados.
  @override
  void dispose() {
    _noteEditor.dispose();

    // Persistência assíncrona do estado do caderno.
    () async {
      try {
        final db = ServiceLocator.instance.db;
        final model = await db.getNotebookById(widget.args.notebookId);
        if (model != null) {
          await db.upsertNotebook(model.copyWith(lastOpened: DateTime.now(), lastPage: _pageIndex));
        }
      } catch (_) {}
    }();
    super.dispose();
  }

  // Carrega metadados do caderno e determina a contagem de páginas.
  // Se o modelo armazenado divergir da contagem real de páginas, faz um upsert para sincronizar.
  Future<void> _initNotebook() async {
    final db = ServiceLocator.instance.db;
    final existing = await db.getAllAnnotations(_nbId);
    if (existing.isNotEmpty) {
      _pageCount = (existing.map((e) => e.pageIndex).fold<int>(0, (m, i) => i > m ? i : m)) + 1;
    } else {
      _pageCount = 1;
    }

    try {
      final model = await db.getNotebookById(widget.args.notebookId);
      if (model != null) {
        _pageIndex = model.lastPage.clamp(0, math.max(0, _pageCount - 1)).toInt();

        if (model.pageCount != _pageCount) {
          await db.upsertNotebook(model.copyWith(pageCount: _pageCount, lastOpened: DateTime.now(), lastPage: _pageIndex));
        }
      }
    } catch (_) {}

    await _loadPage(_pageIndex);
    setState(() {});
  }

  // Carrega as anotações guardadas para a página `i` para as estruturas locais (_strokes, _textNotes, ...)
  // Também reinicia transformações visuais e recalcula limites do papel.
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

    _ivController.value = Matrix4.identity();
    _currentScale = 1.0;
    _handMode = false;
    _canvasIgnore = false;

    _openedNoteIndex = null;
    _noteEditor.clear();

    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePaperRect());
  }

  // Persiste as anotações atuais da página ativa no armazenamento.
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

  // Navega para a página `i`, opcionalmente guardando a página atual antes.
  Future<void> _goTo(int i, {bool saveCurrent = true}) async {
    if (i < 0 || i >= _pageCount || i == _pageIndex) return;
    if (saveCurrent) await _savePage();
    await _loadPage(i);
    setState(() => _pageIndex = i);
  }
  // Adiciona uma nova página ao final do caderno, guarda a atual e atualiza o modelo persistido.
  Future<void> _addPage() async {
    await _savePage();
    setState(() => _pageCount += 1);
    await _goTo(_pageCount - 1);
    try {
      final db = ServiceLocator.instance.db;
      final model = await db.getNotebookById(widget.args.notebookId);
      if (model != null) {
        await db.upsertNotebook(model.copyWith(pageCount: _pageCount, lastOpened: DateTime.now(), lastPage: _pageIndex));
      }
    } catch (_) {}
  }

  // Remove a página atual após confirmação do utilizador.
  Future<void> _removeCurrentPage() async {
    if (_pageCount <= 1) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover página'),
        content: const Text('Tens a certeza de que queres apagar a página atual? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (confirm != true) return;

    final db = ServiceLocator.instance.db;

    await db.deleteAnnotations(_nbId, pageIndex: _pageIndex);
    await db.deleteNotebookPages(_nbId, pageIndex: _pageIndex);

    final remainingAnn = await db.getAllAnnotations(_nbId);
    final toShiftAnn = remainingAnn.where((p) => p.pageIndex > _pageIndex).toList()
      ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));

    for (final p in toShiftAnn) {
      await db.deleteAnnotations(_nbId, pageIndex: p.pageIndex);
      final shifted = PageAnnotations(
        pdfId: p.pdfId,
        pageIndex: p.pageIndex - 1,
        strokes: List.of(p.strokes),
        textNotes: List.of(p.textNotes),
        audioNotes: List.of(p.audioNotes),
        imageNotes: List.of(p.imageNotes),
      );
      await db.savePageAnnotations(shifted);
    }

    final remainingNb = await db.getAllNotebookPages(_nbId);
    final toShiftNb = remainingNb.where((p) => p.pageIndex > _pageIndex).toList()
      ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));

    for (final p in toShiftNb) {
      await db.deleteNotebookPages(_nbId, pageIndex: p.pageIndex);
      final shifted = PageAnnotations(
        pdfId: p.pdfId,
        pageIndex: p.pageIndex - 1,
        strokes: List.of(p.strokes),
        textNotes: List.of(p.textNotes),
        audioNotes: List.of(p.audioNotes),
        imageNotes: List.of(p.imageNotes),
      );
      await db.saveNotebookPage(notebookId: _nbId, pageIndex: p.pageIndex - 1, page: shifted);
    }

    final nextIndex = _pageIndex.clamp(0, _pageCount - 2);

    await _loadPage(nextIndex);
    setState(() {
      _pageCount -= 1;
      _pageIndex = nextIndex;
    });

    try {
      final model = await db.getNotebookById(widget.args.notebookId);
      if (model != null) {
        final newLast = (_pageIndex <= model.lastPage && model.lastPage > 0) ? (model.lastPage - 1) : model.lastPage.clamp(0, math.max(0, _pageCount - 1)).toInt();
        await db.upsertNotebook(model.copyWith(pageCount: _pageCount, lastOpened: DateTime.now(), lastPage: newLast));
      }
    } catch (_) {}
  }


  // Aplica o snapshot de 'undo': restaura o último estado salvo e persiste a página.
  Future<void> _onUndo() async {
    if (_undoStack.isEmpty) return;

    _redoStack.add(_cloneStrokes(_strokes));

    final prev = _undoStack.removeLast();
    setState(() {
      _strokes
        ..clear()
        ..addAll(prev.map((s) => _cloneStroke(s)));
    });
    await _savePage();
  }

  // Aplica o snapshot de 'redo': restaura o próximo estado e persiste a página.
  Future<void> _onRedo() async {
    if (_redoStack.isEmpty) return;

    _undoStack.add(_cloneStrokes(_strokes));
    final next = _redoStack.removeLast();
    setState(() {
      _strokes
        ..clear()
        ..addAll(next.map((s) => _cloneStroke(s)));
    });
    await _savePage();
  }

  // Utilitários para clonar strokes (usados por undo/redo).
  List<Stroke> _cloneStrokes(List<Stroke> src) => src.map((s) => _cloneStroke(s)).toList();

  Stroke _cloneStroke(Stroke s) => Stroke(points: List.of(s.points), width: s.width, color: s.color, mode: s.mode);

  // Regista o estado atual no histórico de undo e limpa a pilha de redo.
  void _pushUndoSnapshot() {
    _undoStack.add(_cloneStrokes(_strokes));

    _redoStack.clear();
  }

  // Cria uma nova nota de texto através de um dialog.
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

  if (!mounted) return;

  final center = _contentCenter(context);
  setState(() => _textNotes.add(TextNote(position: center, text: text)));
    await _savePage();
  }

  // Abre o painel de edição de nota .
  void _openNoteSheet(int index) {
    _openedNoteIndex = index;
    _noteEditor.text = _textNotes[index].text;
    setState(() {});
  }

  // Fecha o painel de edição de nota e limpa o editor.
  void _closeNoteSheet() {
    _openedNoteIndex = null;
    _noteEditor.clear();
    setState(() {});
  }

  // Remove a nota de texto atualmente aberta (se existir) e persiste a página.
  Future<void> _deleteOpenedNote() async {
    if (_openedNoteIndex == null) return;
    final i = _openedNoteIndex!;
    setState(() {
      _textNotes.removeAt(i);
      _openedNoteIndex = null;
    });
    await _savePage();
  }

  // Aplica o texto editado à nota aberta e guarda a página.
  Future<void> _applyNoteText(String v) async {
    if (_openedNoteIndex == null) return;
    final i = _openedNoteIndex!;
    final n = _textNotes[i];
    setState(() => _textNotes[i] = TextNote(position: n.position, text: v.trim()));
    await _savePage();
  }

  // Importa uma imagem da galeria, copia para o storage da app e a insere como nota de imagem centrada.
  Future<void> _importImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;

    final src = x.path;
    final storage = ServiceLocator.instance.storage;
    final root = await storage.appRoot();
    final imagesDir = p.join(root, 'images');

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

  // Calcula a posição do centro do conteúdo, tendo em conta a transformação atual.
  Offset _contentCenter(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return const Offset(0, 0);
    final size = box.size;
    final center = Offset(size.width / 2, size.height / 2);
    final inv = Matrix4.inverted(_ivController.value);
    return MatrixUtils.transformPoint(inv, center);
  }

  // Atualiza o rect com os limites do papel no ecrã.
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

    // O método build compõe a UI principal do ecrã. A estrutura é:
    // - AppBar: título e ações rápidas (importar imagem, re-centrar)
    // - FloatingActionButton (central): gravação de áudio.
    // - BottomAppBar: navegação entre páginas e ações de gestão (adicionar/remover)
    // - Corpo: AnnotationToolbar + área do papel.
    // - NoteBottomSheet: painel inferior para editar notas de texto.
    return Scaffold(
      // Barra superior com título e ações utilitárias.
      appBar: AppBar(
        title: Text('${widget.args.name} (${_pageIndex + 1}/$_pageCount)'),
        actions: [
          // Importar uma imagem para inserir como nota de imagem.
          IconButton(
            tooltip: 'Importar imagem',
            onPressed: _importImage,
            icon: const Icon(Icons.image_outlined),
          ),
          // Repor a transformação do InteractiveViewer para o estado inicial.
          IconButton(
            tooltip: 'Repor enquadramento',
            onPressed: () => setState(() => _ivController.value = Matrix4.identity()),
            icon: const Icon(Icons.center_focus_strong),
          ),
        ],
      ),

      // Botão de ação flutuante centralizado (usado para gravação de áudio). 
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Builder(
        builder: (ctx) => WhatsAppMicButton(
          provideDirPath: () async => ServiceLocator.instance.storage.audioDir(),
          onSaved: (path, durMs) async {
            // Ao guardar um áudio, inserimos um AudioNote e persistimos a página.
            final center = _contentCenter(ctx);
            setState(() => _audioNotes.add(AudioNote(position: center, filePath: path, durationMs: durMs)));
            await _savePage();
          },
        ),
      ),

      // Barra inferior: navegação de páginas e ações principais do caderno.
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 10,
        height: 64,
        child: Row(
          children: [
            // Ir para a página anterior.
            IconButton(
              onPressed: canPrev ? () => _goTo(_pageIndex - 1) : null,
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Anterior',
            ),

            // Alterna o modo mão/desenho (quando a caneta não está presente).
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

            // Criar uma nova nota de texto.
            IconButton.filledTonal(
              tooltip: 'Nova nota de texto',
              onPressed: _createTextNote,
              icon: const Icon(Icons.notes_rounded),
            ),

            const Spacer(),
            // Apagar página (com confirmação) e adicionar nova página.
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

      // Corpo principal do ecrã: toolbar + área do papel com camadas de anotações.
      body: Stack(
        children: [
          Column(
            children: [
              // Barra de ferramentas de anotação: controlos de modo, largura, cor, undo/redo, etc.
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
                  enabled: !_handMode,
                  eraserWidth: _eraserWidth,
                  onEraserWidthChanged: (v) => setState(() => _eraserWidth = v),
                  ownerId: widget.args.notebookId,
                  ownerIsNotebook: true,
                ),
              ),
              // Área expansível que contém o InteractiveViewer (zoom/pan) e o papel.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: ClipRect(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return InteractiveViewer(
                          transformationController: _ivController,

                          // O pan fica desativado quando há contacto por caneta (ou se aceitamos mão).
                          panEnabled: !_stylusDown && (_stylusEverSeen ? true : _handMode),
                          minScale: 1.0,
                          maxScale: 5.0,
                          boundaryMargin: EdgeInsets.zero,
                          clipBehavior: Clip.hardEdge,
                          scaleEnabled: true,
                          onInteractionUpdate: (_) {
                            // Atualiza escala corrente e recalcula rect do papel após interação.
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

                                  // A camada do 'papel': É apenas um background com sombra.
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

                                  // Camada principal de desenho: DrawingCanvas recebe todos os strokes.
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

                                  // Camada de pins de áudio.
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

                                  // Camada de notas de imagem.
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

                                  // Camada de notas de texto.
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

          // Painel inferior para edição de notas.
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

// Pequeno painel inferior usado para editar o texto de uma nota.
//
// Comportamento e contrato:
// - `visible`: controla se o painel está visível (animação de slide para dentro/fora).
// - `controller`: controller do TextField usado para editar o texto.
// - `onChanged`: callback invocado quando o texto muda (usado para persistir atualizações).
// - `onClose`: fecha o painel sem apagar a nota.
// - `onDelete`: função assíncrona chamada para apagar a nota atualmente editada.
// - `bottomBarHeight`: altura da barra inferior do Scaffold (usada para deslocar o painel e evitar sobreposição).

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
    // Altura inferior do ecrã que devemos considerar para não sobrepor controlos do sistema.
    final pad = MediaQuery.of(context).padding.bottom;
    // Esquema de cores atual usado para o background.
    final base = Theme.of(context).colorScheme;
    // Altura fixa do painel.
    const height = 140.0;

    // Estrutura do widget:
    // - Align/AnimatedSlide: posiciona e anima a entrada/saída do painel a partir de baixo.
    // - Padding: desloca o painel para cima o suficiente para evitar a BottomAppBar + safe area.
    // - Material: cartão elevado com borda arredondada para o visual do painel.
    // - SizedBox/Padding/Column: conteúdo com título, ações e o TextField expansível.
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
                        // Ícone e título do painel.
                        const Icon(Icons.sticky_note_2_outlined, size: 18),
                        const SizedBox(width: 6),
                        const Expanded(child: Text('Nota', style: TextStyle(fontWeight: FontWeight.w600))),
                        // Botão apagar.
                        IconButton(
                          tooltip: 'Apagar',
                          onPressed: () async => await onDelete(),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                        // Botão fechar.
                        IconButton(
                          tooltip: 'Fechar',
                          onPressed: onClose,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Campo de edição de texto.
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
