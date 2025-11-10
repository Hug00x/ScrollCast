import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../main.dart';
import '../../models/pdf_document_model.dart';
import '../screens/pdf_viewer_screen.dart';

/*
  LibraryScreen

  Propósito geral:
  - Apresenta a lista de PDFs importados pelo utilizador.
  - Permite pesquisar, marcar favoritos, importar novos PDFs e apagar
    PDFs (com limpeza de ficheiros e anotações associadas).
  - Usa o DatabaseService (via ServiceLocator) para operações persistentes
    e mantém um conjunto em memória de favoritos para UI rápida.

  Organização do ficheiro:
  - `_LibraryScreenState` contém o estado da lista, pesquisa, favoritos
    e os métodos para importar/apagar PDFs.
  - `build()` monta a AppBar com uma barra de pesquisa e a listagem
    dos PDFs, além do FAB para importar.
*/

class LibraryScreen extends StatefulWidget {
  static const route = '/';
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<PdfDocumentModel> _items = [];
  bool _busy = false;

  // Favoritos em memória.
  Set<String> _favIds = <String>{};
  StreamSubscription<void>? _favSub;

  // FIltro de pesquisa.
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Inicialização: carrega a lista de PDFs e subscreve eventos de
    // favoritos para atualizar a UI quando algo mudar noutra parte da app.
    _load();
    _favSub = ServiceLocator.instance.db.favoritesEvents().listen((_) {
      _loadFavorites();
    });
  }

  @override
  void dispose() {
    // Limpeza de timers/subscrições e controllers ao desmontar o widget.
    _debounce?.cancel();
    _favSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Carrega os PDFs (com o filtro de pesquisa `_query`) ordenando por última abertura. 
    // Também carrega os favoritos para manter o estado visual consistente.
    final docs = await ServiceLocator.instance.db.listPdfs(query: _query);
    docs.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    final favDocs = await ServiceLocator.instance.db.listFavorites();
    if (!mounted) return;
    setState(() {
      _items = docs;
      _favIds = favDocs.map((e) => e.id).toSet();
    });
  }

  Future<void> _loadFavorites() async {
    // Recarrega apenas os favoritos (utilizado quando a fonte de favoritos
    // em DatabaseService emite um evento para sincronizar a UI).
    final favDocs = await ServiceLocator.instance.db.listFavorites();
    if (!mounted) return;
    setState(() {
      _favIds = favDocs.map((e) => e.id).toSet();
    });
  }

  void _onSearchChanged(String value) {
    // Debounce simples para evitar disparar muitas pesquisas enquanto o
    // utilizador digita: espera 180ms após a última tecla.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      _query = value.trim();
      _load();
    });
  }

  Future<void> _toggleFavorite(PdfDocumentModel d) async {
    // Alterna o estado de favorito no DatabaseService e atualiza o set
    // local `_favIds` para resposta imediata na UI.
    final isFav = _favIds.contains(d.id);
    await ServiceLocator.instance.db.setFavorite(d.id, !isFav);
    if (!mounted) return;
    setState(() {
      if (isFav) {
        _favIds.remove(d.id);
      } else {
        _favIds.add(d.id);
      }
    });
  }

  Future<void> _importPdf() async {
    // Importa um ficheiro PDF via file picker, copia-o para a pasta da
    // aplicação, obtém o número de páginas e regista um novo modelo no DB.
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: false,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      final srcPath = file.path!;
      final storage = ServiceLocator.instance.storage;
      final destDir = await storage.appRoot();
      final newPath = await storage.createUniqueFilePath(destDir, extension: 'pdf');
      await storage.copyFile(srcPath, newPath);

      final count = await ServiceLocator.instance.pdf.getPageCount(newPath);
      final id = const Uuid().v4();
      final model = PdfDocumentModel(
        id: id,
        name: file.name,
        originalPath: newPath,
        pageCount: count,
        lastOpened: DateTime.now(),
        lastPage: 0,
      );
      await ServiceLocator.instance.db.upsertPdf(model);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF importado')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha a importar: $e')),
        );
      }
    }
  }
  //Apaga um PDF e todos os recursos associados (anotações, áudios, imagens, notas)
  Future<void> _deletePdf(PdfDocumentModel d) async {
    if (_busy) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar PDF'),
        content: Text(
          'Tens a certeza que queres apagar "${d.name}"?\n'
          'Isto remove o ficheiro, as anotações, os áudios e imagens associadas.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (confirm != true) return;
    
    // Ao tentar apagar, o processo é envolvido em try/catch para notificar o utilizador em caso
    // de erro e usamos `_busy` para bloquear interacções enquanto decorre.
    setState(() => _busy = true);
    final db = ServiceLocator.instance.db;
    final storage = ServiceLocator.instance.storage;

    try {
      final all = await db.getAllAnnotations(d.id);
      for (final p in all) {
        for (final a in p.audioNotes) {
          await storage.deleteIfExists(a.filePath);
        }
      }
      await storage.deleteIfExists(d.originalPath);
      if (d.annotatedPath != null) {
        await storage.deleteIfExists(d.annotatedPath!);
      }
      await db.deletePdf(d.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Apagado: ${d.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao apagar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Shader _titleGradient(Rect bounds) {
    return const LinearGradient(
      colors: [
        Color(0xFFFFC107),
        Color(0xFF4CAF50),
        Color(0xFF26C6DA),
      ],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    ).createShader(bounds);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // cor visível para ícone não-favorito (claro e escuro)
    final Color unfavColor = cs.onSurfaceVariant.withAlpha((0.55 * 255).round());

  // ===== Build: AppBar com pesquisa + listagem de PDFs =====
  // A AppBar contém um campo de pesquisa. O corpo mostra
  // a lista de PDFs (ou uma mensagem vazia) e inclui um FAB para importar.
  return Scaffold(
      appBar: AppBar(
        title: const Text('Os meus PDFs'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Pesquisar PDFs…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                fillColor: cs.surface.withAlpha((.65 * 255).round()),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.transparent),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: cs.primary),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          _items.isEmpty
              ? const Center(child: Text('Sem PDFs. Importa um PDF para começar.'))
              : ListView.separated(
                  itemCount: _items.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = _items[i];
                    final isFav = _favIds.contains(d.id);
                    // ----- Item da lista de PDF -----
                    // Cada ListTile mostra o estado de favorito, o
                    // título com gradiente, subtítulo com contagem de páginas,
                    // ação de abertura ao tocar e ações rápidas no trailing.
                    return ListTile(
                      // Leading: ícone de favorito; tocar alterna o estado.
                      leading: InkResponse(
                        onTap: () => _toggleFavorite(d),
                        radius: 24,
                        child: isFav
                            ? ShaderMask(
                                shaderCallback: _titleGradient,
                                blendMode: BlendMode.srcIn,
                                child: const Icon(Icons.star, size: 24),
                              )
                            : Icon(Icons.star_border, size: 24, color: unfavColor),
                      ),
                      // Title: aplica o gradiente.
                      title: ShaderMask(
                        shaderCallback: _titleGradient,
                        blendMode: BlendMode.srcIn,
                        child: Text(
                          d.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      // Subtitle: informação auxiliar (páginas).
                      subtitle: Text('${d.pageCount} páginas'),
                      // onTap: abre o PdfViewerScreen; ao regressar recarrega a lista
                      // para refletir possíveis mudanças feitas durante a edição.
                      onTap: () => Navigator.pushNamed(
                        context,
                        PdfViewerScreen.route,
                        arguments: PdfViewerArgs(
                          pdfId: d.id,
                          name: d.name,
                          path: d.originalPath,
                        ),
                      ).then((_) => _load()),
                      // Trailing: ações rápidas: apagar e chevron (indicador visual).
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              tooltip: 'Apagar',
                              onPressed: () => _deletePdf(d),
                              icon: const Icon(Icons.delete_outline_rounded)
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    );
                  },
                ),
          //Overlay de carregamento
          if (_busy)
            const Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Color(0x88000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
      //Botão flutuante para importar PDFs
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'library_import_fab',
        onPressed: _busy ? null : _importPdf,
        label: const Text('Importar PDF'),
        icon: const Icon(Icons.file_open),
      ),
    );
  }
}
