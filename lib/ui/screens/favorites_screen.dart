import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../main.dart';
import '../../models/pdf_document_model.dart';
import '../../models/notebook_model.dart';
import 'pdf_viewer_screen.dart';
import 'notebook_viewer_screen.dart';

/*
  FavoriteScreen

  Propósito geral:
  - Apresenta uma vista consolidada de todos os favoritos do utilizador,
    incluindo PDFs (guardados no DatabaseService) e Cadernos (guardados
    localmente em Hive por performance e simplicidade).
  - Permite pesquisar, abrir e remover itens dos favoritos.

  Organização do ficheiro:
  - `_FavoriteScreenState` contém o estado (listas de PDFs e cadernos,
    subscrições para eventos de favoritos, e o controlador de pesquisa).
  - Lifecycle: inicialização de subscrições e boxes Hive, limpeza em dispose.
  - Métodos de carga (`_load`, `_loadPdfs`, `_loadNotebooks`) mantêm os dados
    sincronizados com o DatabaseService e com a box Hive local.
  - A UI tem um AppBar com pesquisa e uma ListView com secções para PDFs e
    para Cadernos. Cada item permite abrir ou remover dos favoritos.
*/

class FavoriteScreen extends StatefulWidget {
  const FavoriteScreen({super.key});
  @override
  State<FavoriteScreen> createState() => _FavoriteScreenState();
}

class _FavoriteScreenState extends State<FavoriteScreen> {
  // Referência ao serviço de base de dados da aplicação.
  final _db = ServiceLocator.instance.db;

  // ----- PDFs favoritos -----
  // A lista de PDFs favoritos exibida na UI.
  List<PdfDocumentModel> _pdfs = [];
  // Subscrição para eventos de alteração de favoritos.
  StreamSubscription<void>? _pdfFavSub;

  // ----- Notebooks favoritos  -----
  // Usamos uma box Hive por utilizador para guardar IDs de favoritos.
  Box? _nbFavBox;
  // Conjunto em memória de IDs de cadernos favoritos para lookup rápido.
  Set<String> _nbFavIds = <String>{};
  // Observador de eventos da box Hive para reagir a alterações externas.
  StreamSubscription<BoxEvent>? _nbFavWatchSub;
  // Lista de NotebookModel filtrada para favoritos e pesquisa.
  List<NotebookModel> _nbs = [];
  // Nome da box, inclui UID para isolamento por utilizador.
  String get _nbFavBoxName =>
      'nb_favorites_${ServiceLocator.instance.auth.currentUid ?? "_anon"}';

  // ----- Filtro de pesquisa -----
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  // ----- Lifecycle: initState -----
  @override
  void initState() {
    super.initState();
    // Subscreve eventos do DatabaseService para atualizar automaticamente
    // a lista de PDFs favoritos quando algo muda.
    _pdfFavSub = _db.favoritesEvents().listen((_) => _load());
    // Inicializa a box Hive e o watcher para favoritos de cadernos.
    _initNotebookFavs();
    // Carrega inicialmente os dados (PDFs + Notebooks favoritos).
    _load();
  }

  // Abre a box Hive para favoritos de cadernos e inicia o watcher que reage a alterações.
  Future<void> _initNotebookFavs() async {
    _nbFavBox = Hive.isBoxOpen(_nbFavBoxName)
        ? Hive.box(_nbFavBoxName)
        : await Hive.openBox(_nbFavBoxName);
    // Preenche o conjunto de IDs a partir das chaves da box.
    _pullNbFavIds();

    // Cancela watcher anterior (se existir) e subscreve o atual.
    _nbFavWatchSub?.cancel();
    _nbFavWatchSub = _nbFavBox!.watch().listen((_) async {
      // Quando a box muda, atualizamos os IDs e recarregamos os notebooks.
      _pullNbFavIds();
      await _loadNotebooks();
    });
  }

  // Preenche `_nbFavIds` com as chaves (IDs) existentes na box Hive.
  void _pullNbFavIds() {
    _nbFavIds = _nbFavBox?.keys.whereType<String>().toSet() ?? <String>{};
  }

  // ----- Lifecycle: dispose -----
  @override
  void dispose() {
    // Cancela subscrições e limpa controllers para evitar leaks.
    _pdfFavSub?.cancel();
    _nbFavWatchSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ----- Carregamento de dados -----
  // Carrega tanto PDFs como Notebooks em paralelo e notifica a UI.
  Future<void> _load() async {
    await Future.wait([
      _loadPdfs(),
      _loadNotebooks(),
    ]);
    if (mounted) setState(() {});
  }

  // Carrega PDFs favoritos a partir do DatabaseService aplicando o filtro
  // de pesquisa `_query` e ordenando por `lastOpened`.
  Future<void> _loadPdfs() async {
    final items = await _db.listFavorites(query: _query);
    items.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    _pdfs = items;
  }

  // Carrega os notebooks, filtra pelos IDs favoritados na box Hive
  // e aplica o filtro de pesquisa local. Ordena por `lastOpened`.
  Future<void> _loadNotebooks() async {
    final all = await _db.listNotebooks();
    var favs = all.where((n) => _nbFavIds.contains(n.id)).toList();
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      favs = favs.where((n) => n.name.toLowerCase().contains(q)).toList();
    }
    favs.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    _nbs = favs;
    if (mounted) setState(() {});
  }

  // ----- Interação de pesquisa -----
  void _onSearchChanged(String value) {
    setState(() {
      _query = value.trim();
    });
    _load();
  }

  // ----- Remoção de favoritos -----
  // Para PDFs delegamos ao DatabaseService (que guarda o estado de favorito).
  Future<void> _removePdfFav(String id) async {
    await _db.setFavorite(id, false);
  }

  // Para cadernos removemos a chave da box Hive e recarregamos a lista.
  Future<void> _removeNbFav(String id) async {
    await _nbFavBox?.delete(id);
    await _loadNotebooks();
  }

  // ----- Helper visual: gradiente aplicado aos títulos -----
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

  // ===== Build: AppBar (com pesquisa) + ListView de secções =====
  // O corpo apresenta secções para PDFs e Cadernos se existirem favoritos.
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favoritos'),
        // Barra de pesquisa na AppBar para filtrar os favoritos.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Pesquisar favoritos…',
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
      body: (_pdfs.isEmpty && _nbs.isEmpty)
          // Mensagem para quando não existem favoritos.
          ? const Center(child: Text('Ainda não tens favoritos.'))
          // Lista com secções: PDFs e Cadernos. Cada item permite abrir
          // o respetivo visualizador e remover dos favoritos.
          : ListView(
              children: [
                if (_pdfs.isNotEmpty) ...[
                  _SectionHeader(title: 'PDFs'),
                  const Divider(height: 1),
                  // Mapeia cada PDF favorito para um ListTile com ações.
                  ..._pdfs.map((d) => ListTile(
                        leading: ShaderMask(
                          shaderCallback: _titleGradient,
                          blendMode: BlendMode.srcIn,
                          child: const Icon(Icons.star, size: 22),
                        ),
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
                        subtitle: Text('${d.pageCount} páginas'),
                        // Abre o visualizador de PDF; ao regressar recarrega os dados.
                        onTap: () => Navigator.pushNamed(
                          context,
                          PdfViewerScreen.route,
                          arguments: PdfViewerArgs(
                            pdfId: d.id,
                            name: d.name,
                            path: d.originalPath,
                          ),
                        ).then((_) => _load()),
                        trailing: IconButton(
                          tooltip: 'Remover dos favoritos',
                          icon: const Icon(Icons.star),
                          onPressed: () => _removePdfFav(d.id),
                        ),
                      )),
                  const SizedBox(height: 12),
                ],
                if (_nbs.isNotEmpty) ...[
                  _SectionHeader(title: 'Cadernos'),
                  const Divider(height: 1),
                  // Cada caderno favorito abre o visualizador de cadernos e
                  // permite remover dos favoritos locais.
                  ..._nbs.map((n) => ListTile(
                        leading: ShaderMask(
                          shaderCallback: _titleGradient,
                          blendMode: BlendMode.srcIn,
                          child: const Icon(Icons.star, size: 22),
                        ),
                        //Título com gradiente aplicado.
                        title: ShaderMask(
                          shaderCallback: _titleGradient,
                          blendMode: BlendMode.srcIn,
                          child: Text(
                            n.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        //Subtitle com número de páginas e pasta onde está guardado.
                        subtitle: Text('${n.pageCount} páginas • ${n.folder ?? "raiz"}'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NotebookViewerScreen(
                                args: NotebookViewerArgs(notebookId: n.id, name: n.name),
                              ),
                            ),
                          ).then((_) => _load());
                        },
                        trailing: IconButton(
                          tooltip: 'Remover dos favoritos',
                          icon: const Icon(Icons.star),
                          onPressed: () => _removeNbFav(n.id),
                        ),
                      )),
                ],
                const SizedBox(height: 8),
              ],
            ),
    );
  }
}

// Pequeno widget utilitário para cabeçalhos de secção (PDFs / Cadernos).
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              letterSpacing: 0.8,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
