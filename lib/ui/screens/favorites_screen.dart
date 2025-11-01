import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../main.dart';
import '../../models/pdf_document_model.dart';
import '../../models/notebook_model.dart';
import 'pdf_viewer_screen.dart';
import 'notebook_viewer_screen.dart';

class FavoriteScreen extends StatefulWidget {
  const FavoriteScreen({super.key});
  @override
  State<FavoriteScreen> createState() => _FavoriteScreenState();
}

class _FavoriteScreenState extends State<FavoriteScreen> {
  final _db = ServiceLocator.instance.db;

  // PDFs
  List<PdfDocumentModel> _pdfs = [];
  StreamSubscription<void>? _pdfFavSub;

  // Notebooks favoritos (Hive)
  Box? _nbFavBox;
  Set<String> _nbFavIds = <String>{};
  StreamSubscription<BoxEvent>? _nbFavWatchSub;
  List<NotebookModel> _nbs = [];
  String get _nbFavBoxName =>
      'nb_favorites_${ServiceLocator.instance.auth.currentUid ?? "_anon"}';

  // pesquisa
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _pdfFavSub = _db.favoritesEvents().listen((_) => _load());
    _initNotebookFavs();
    _load();
  }

  Future<void> _initNotebookFavs() async {
    _nbFavBox = Hive.isBoxOpen(_nbFavBoxName)
        ? Hive.box(_nbFavBoxName)
        : await Hive.openBox(_nbFavBoxName);
    _pullNbFavIds();

    _nbFavWatchSub?.cancel();
    _nbFavWatchSub = _nbFavBox!.watch().listen((_) async {
      _pullNbFavIds();
      await _loadNotebooks();
    });
  }

  void _pullNbFavIds() {
    _nbFavIds = _nbFavBox?.keys.whereType<String>().toSet() ?? <String>{};
  }

  @override
  void dispose() {
    _pdfFavSub?.cancel();
    _nbFavWatchSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await Future.wait([
      _loadPdfs(),
      _loadNotebooks(),
    ]);
    if (mounted) setState(() {});
  }

  Future<void> _loadPdfs() async {
    final items = await _db.listFavorites(query: _query);
    items.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    _pdfs = items;
  }

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

  void _onSearchChanged(String value) {
    setState(() {
      _query = value.trim();
    });
    _load();
  }

  Future<void> _removePdfFav(String id) async {
    await _db.setFavorite(id, false);
  }

  Future<void> _removeNbFav(String id) async {
    await _nbFavBox?.delete(id);
    await _loadNotebooks();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favoritos'),
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
          ? const Center(child: Text('Ainda não tens favoritos.'))
          : ListView(
              children: [
                if (_pdfs.isNotEmpty) ...[
                  _SectionHeader(title: 'PDFs'),
                  const Divider(height: 1),
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
                  ..._nbs.map((n) => ListTile(
                        leading: ShaderMask(
                          shaderCallback: _titleGradient,
                          blendMode: BlendMode.srcIn,
                          child: const Icon(Icons.star, size: 22),
                        ),
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
