import 'dart:typed_data';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';
import '../widgets/text_note_bubble.dart';
import '../../main.dart';
import '../../models/annotations.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/annotation_toolbar.dart';
import '../widgets/whatsapp_mic_button.dart';
import '../widgets/audio_pin_layer.dart';
import '../widgets/image_note_widget.dart';

/*
  Pdf viewer screen

  Propósito geral:
  - Fornece a interface para visualizar documentos PDF, navegar entre páginas,
    renderizar páginas para imagem e permitir anotações ricas (strokes, notas de
    texto, áudio e imagens). Permite também importar imagens e gravar
    excertos de áudio.
  - Persiste anotações por página usando o serviço de base de dados (`ServiceLocator.instance.db`) e
    guarda metadados do documento (última página aberta) para restaurar o estado.

  Organização do ficheiro:
  - `PdfViewerArgs`: argumentos simples para abrir o ecrã (id, nome e caminho do ficheiro).
  - `PdfViewerScreen` + `_PdfViewerScreenState`: widget de estado que orquestra renderização,
    carregamento/guardar de anotações, e a UI principal (toolbar, canvas, camadas de notas).
*/

// ===== PdfViewerArgs =====
// Pequeno objeto de valor que transporta a identidade e o caminho do PDF
// a abrir. Mantemos isto separado para que o ecrã possa ser construído
// a partir de argumentos de navegação sem depender de modelos completos.
class PdfViewerArgs {
  final String pdfId;
  final String name;
  final String path;
  const PdfViewerArgs({required this.pdfId, required this.name, required this.path});
}

// ===== PdfViewerScreen=====
// Ecrã com estado que hospeda o motor de renderização do PDF, as camadas
// de anotação e a toolbar de anotação.
class PdfViewerScreen extends StatefulWidget {
  static const route = '/pdf';
  final PdfViewerArgs args;
  const PdfViewerScreen({super.key, required this.args});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  // ===== Estado: documento e navegação =====
  // `_pageCount` é o número de páginas do PDF. `_pageIndex` é a página atualmente visível.
  int _pageCount = 1;
  int _pageIndex = 0;

  // Cache de imagens renderizadas por página (em memória).
  final _pageCache = <int, Uint8List>{};
  Uint8List? get _pageBytes => _pageCache[_pageIndex];

  // ===== Estado das camadas de anotação =====
  // Strokes para desenho livre e pilhas de undo/redo. Notas de áudio/texto/
  // imagem são coleções separadas e persistidas por página.
  final _strokes = <Stroke>[];
  final List<List<Stroke>> _undoStack = [];
  final List<List<Stroke>> _redoStack = [];
  final _audioNotes = <AudioNote>[];
  final _textNotes = <TextNote>[];
  final _imageNotes = <ImageNote>[];

  // O tamanho disponível para sobrepor notas e imagens. Atualizado por um
  // LayoutBuilder para permitir calcular tamanhos por defeito adequados.
  Size _imgSize = const Size(1, 1);

  // Configuração de desenho exposta pela toolbar.
  StrokeMode _mode = StrokeMode.pen;
  double _width = 4;
  int _color = 0xFF000000;
  double _eraserWidth = 18;

  // Controller do InteractiveViewer e flags derivadas.
  final _ivController = TransformationController();
  bool _canvasIgnore = false;
  double _currentScale = 1.0;

  // Estado UI: `handMode` altera o comportamento de input para arrastar,
  // `_loading` indica que a renderização/inicialização ainda está em curso.
  bool _handMode = false;
  bool _loading = true;

  // Estado de deteção de stylus. Tratamos a caneta de forma especial para
  // permitir que os dedos continuem a pan/zoom enquanto a caneta desenha.
  bool _stylusDown = false;
  bool _stylusEverSeen = false;

  // Estado do editor de notas de texto: índice da nota aberta (ou null)
  // e o controller usado pelo painel inferior de edição.
  int? _openedNoteIndex;
  final _noteEditor = TextEditingController();

  // Key e rect que descrevem a área visível do 'papel'. `_paperRect` é
  // usado para limitar as posições dos pinos e garantir que as notas ficam
  // dentro dos limites do documento.
  final GlobalKey _paperKey = GlobalKey();
  Rect? _paperRect;

  // ===== Ciclo de vida & inicialização =====
  // Os métodos abaixo executam a sequência de arranque do documento:

  @override
  void initState() {
    super.initState();
    _initDoc();
  }

  Future<void> _initDoc() async {
    // Marca carregamento e determina o número de páginas do PDF.
    // Guardamos o resultado em `_pageCount` para navegação e exibição do título.
    setState(() => _loading = true);
    final pdf = ServiceLocator.instance.pdf;
    final db = ServiceLocator.instance.db;
    final count = await pdf.getPageCount(widget.args.path);
    setState(() => _pageCount = count);

    // Tenta restaurar a última página guardada no modelo persistido.
    try {
      final model = await db.getPdfById(widget.args.pdfId);
      if (model != null) {
        final last = model.lastPage.clamp(0, math.max(0, count - 1)).toInt();
        _pageIndex = last;
      }
    } catch (_) {}

    // Assegura que a página inicial está renderizada e carrega anotações associadas.
    await _ensureRendered(_pageIndex);
    await _loadAnnotations(_pageIndex);
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _noteEditor.dispose();
    () async {
      try {
        final db = ServiceLocator.instance.db;
        final model = await db.getPdfById(widget.args.pdfId);
        if (model != null) {
          await db.upsertPdf(model.copyWith(lastOpened: DateTime.now(), lastPage: _pageIndex));
        }
      } catch (_) {}
    }();
    super.dispose();
  }

  // ===== Renderização & anotações =====
  // Helpers para renderizar páginas para memória, carregar/guardar as
  // anotações por página e atualizar o rect visível do papel usado pelas lentes.

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

    // Após o frame calculamos o rect do papel para que as sobreposições
    // possam ser posicionadas corretamente relativamente à imagem da página visível.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePaperRect());
  }

  // ===== Cálculo do rect do papel =====
  // Calcula a área do documento em coordenadas globais; o resultado é
  // usado pelas camadas de sobreposição para limitar posições.
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

  // Persiste as anotações da página atual na base de dados.
  Future<void> _savePage() async {
    await ServiceLocator.instance.db.savePageAnnotations(
      PageAnnotations(
        pdfId: widget.args.pdfId,
        pageIndex: _pageIndex,
        strokes: List.of(_strokes),
        audioNotes: List.of(_audioNotes),
        textNotes: List.of(_textNotes),
        imageNotes: List.of(_imageNotes),
      ),
    );
  }

  // Navega para a página `i`: guarda a página atual, garante que a nova
  // página está renderizada e carrega as suas anotações.
  Future<void> _goTo(int i) async {
    if (i < 0 || i >= _pageCount || i == _pageIndex) return;
    await _savePage();
    await _ensureRendered(i);
    await _loadAnnotations(i);
    setState(() => _pageIndex = i);
  }

  // ===== Undo/Redo & utilitários de desenho =====
  // Suporte para as pilhas de undo/redo e helpers para clonar strokes..

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

  List<Stroke> _cloneStrokes(List<Stroke> src) => src.map((s) => _cloneStroke(s)).toList();

  Stroke _cloneStroke(Stroke s) => Stroke(points: List.of(s.points), width: s.width, color: s.color, mode: s.mode);

  void _pushUndoSnapshot() {
    _undoStack.add(_cloneStrokes(_strokes));
    _redoStack.clear();
  }

  // ===== Conversões de coordenadas & operações de notas =====
  // Utilitários que fazem o mapeamento entre coordenadas globais/da vista
  // e o sistema de coordenadas do canvas, além de operações para criar, editar e importar notas.

  Offset _contentCenter(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return const Offset(0, 0);
    final size = box.size;
    final center = Offset(size.width / 2, size.height / 2);
    final inv = Matrix4.inverted(_ivController.value);
    return MatrixUtils.transformPoint(inv, center);
  }

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

    // Insere uma nota de texto centrada na vista atual. `_contentCenter`
    // converte o centro do viewport para coordenadas do canvas para que
    // a nota apareça no mesmo local quando o utilizador abrir o editor.
    final center = _contentCenter(context);
    setState(() => _textNotes.add(TextNote(position: center, text: text)));
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
    try {
      final d = Directory(imagesDir);
      if (!await d.exists()) await d.create(recursive: true);
    } catch (_) {}
    final ext = p.extension(src).replaceFirst('.', '');
    final dest = await storage.createUniqueFilePath(imagesDir, extension: ext.isEmpty ? 'jpg' : ext);
    await storage.copyFile(src, dest);

  if (!mounted) return;
  // Coloca a imagem importada no centro do viewport e calcula um tamanho
  // por defeito razoável com base na imagem da página.
  final center = _contentCenter(context);
  final defaultSize = math.min(_imgSize.width, _imgSize.height) * 0.3;
    setState(() => _imageNotes.add(ImageNote(position: center, filePath: dest, width: defaultSize, height: defaultSize)));
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

  @override
  Widget build(BuildContext context) {
    // ===== Build: árvore principal da UI =====
    // O build compõe a UI completa: AppBar, FAB, BottomAppBar, AnnotationToolbar
    // e o InteractiveViewer com todas as camadas de anotação.
    if (_loading || _pageBytes == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Flags de navegação e estado do painel
    final canPrev = _pageIndex > 0;
    final canNext = _pageIndex < _pageCount - 1;
    final sheetOpen = _openedNoteIndex != null;

  // Estrutura principal:
  // - AppBar com título do documento e indicador de página
  // - FAB central para captura de áudio
  // - BottomAppBar para navegação e ações rápidas
  // - Corpo: Toolbar + InteractiveViewer + camadas de sobreposição
  //   (desenho, pinos, imagens, notas de texto)
  // - Painel inferior de edição de notas que aparece ao editar uma nota de texto
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.args.name} (${_pageIndex + 1}/$_pageCount)'),
        actions: [
          // Importar imagem local para inserir na página atual.
          IconButton(
            tooltip: 'Importar imagem',
            onPressed: _importImage,
            icon: const Icon(Icons.image_outlined),
          ),
          // Repor transformações (zoom/pan) para o estado inicial.
          IconButton(
            tooltip: 'Repor enquadramento',
            onPressed: () => setState(() => _ivController.value = Matrix4.identity()),
            icon: const Icon(Icons.center_focus_strong),
          ),
        ],
      ),

  // Botão flutuante para captura de áudio.
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

  // Barra de navegação inferior: navegação por páginas, alternância do modo mão
  // e ações rápidas.
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
              // Toolbar de anotação: modo, largura, cor, undo/redo e cores recentes.
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
                  ownerId: widget.args.pdfId,
                  ownerIsNotebook: false,
                ),
              ),
              // Área expansível que contém o InteractiveViewer e todas as
              // camadas de sobreposição. Usamos FittedBox + ConstrainedBox
              // para manter a relação de aspeto da página enquanto ela se ajusta.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: ClipRect(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return InteractiveViewer(
                          transformationController: _ivController,
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
                                  // Imagem renderizada da página.
                                  Center(child: Image.memory(_pageBytes!, gaplessPlayback: true)),
                                  // Calcula o tamanho disponível para imagens e notas.
                                  Positioned.fill(
                                    child: LayoutBuilder(
                                      builder: (_, c2) {
                                        _imgSize = Size(c2.maxWidth, c2.maxHeight);
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                  ),
                                  // Camada de desenho: recebe os strokes e expõe callbacks
                                  // usados para persistir alterações e registar snapshots de undo.
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      ignoring: (!_stylusDown) && (_handMode || _canvasIgnore),
                                      child: DrawingCanvas(
                                        key: ValueKey('canvas-$_pageIndex'),
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
                                          if (ignore != _canvasIgnore) setState(() => _canvasIgnore = ignore);
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
                                  // Camada de pinos de áudio.
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
                                      allowedBounds: _paperRect,
                                    ),
                                  ),

                                  // Camada de notas de imagem.
                                  ..._imageNotes.indexed.map((entry) {
                                    final idx = entry.$1;
                                    final note = entry.$2;
                                    return ImageNoteWidget(
                                      key: ValueKey('img-$idx-$_pageIndex'),
                                      note: note,
                                      canvasSize: _imgSize,
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
                                      key: ValueKey('txtpin-$idx-$_pageIndex'),
                                      note: note,
                                      canvasSize: _imgSize,
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

          // Painel inferior de edição de notas. Animado para dentro da vista
          // quando uma nota de texto é aberta; contém o editor e ações (apagar/fechar).
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

// ===== _NoteBottomSheet =====
// Painel inferior reutilizável para editar o texto de uma nota.
// Comportamento e responsabilidades:
// - É apenas um widget de apresentação  que recebe callbacks
//   para aplicar/fechar/apagar a nota.
// - Adapta a sua posição ao espaço seguro inferior para evitar
//   ser sobreposto por gestos do sistema ou pelo teclado.
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
    // ===== Build do painel inferior =====
    // `pad` ajusta o painel ao espaço seguro na parte inferior. `base` obtém a paleta de cores do tema. `height`
    // é a altura visual desejada do painel — mantemos fixo para evitar
    // saltos de layout ao abrir/fechar.
    final pad = MediaQuery.of(context).padding.bottom;
    final base = Theme.of(context).colorScheme;
    const height = 140.0;

    // A hierarquia abaixo monta o cartão do painel com elevação e canto
    // arredondado, adiciona padding lateral e inferior para separar do
    // BottomAppBar e anima a sua entrada/saída verticalmente.
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedSlide(
        // Duração e curva escolhidas para uma transição suave e rápida.
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        // Quando `visible` é falso deslocamos o painel para baixo.
        offset: visible ? Offset.zero : const Offset(0, 1.2),
        child: Padding(
          // O padding inferior inclui a altura da barra inferior ativa e o
          // espaço seguro para evitar sobreposição com gestos/teclado.
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
                    // Cabeçalho do painel: ícone, título e ações (apagar/fechar).
                    Row(
                      children: [
                        const Icon(Icons.sticky_note_2_outlined, size: 18),
                        const SizedBox(width: 6),
                        const Expanded(child: Text('Nota', style: TextStyle(fontWeight: FontWeight.w600))),
                        // Apagar invoca o callback `onDelete`.
                        IconButton(
                          tooltip: 'Apagar',
                          onPressed: () async => await onDelete(),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                        // Fechar simplesmente notifica o callback `onClose`.
                        IconButton(
                          tooltip: 'Fechar',
                          onPressed: onClose,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Editor de texto expansível. `onChanged` propaga alterações
                    // em tempo real para o estado da página, que por sua vez persiste quando apropriado.
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
