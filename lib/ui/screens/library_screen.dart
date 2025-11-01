// lib/ui/screens/library_screen.dart
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../main.dart';
import '../../models/pdf_document_model.dart';
import '../screens/pdf_viewer_screen.dart';

class LibraryScreen extends StatefulWidget {
  static const route = '/';
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<PdfDocumentModel> _items = [];
  bool _busy = false;

  // favoritos em memória + sub de eventos
  Set<String> _favIds = <String>{};
  StreamSubscription<void>? _favSub;

  // pesquisa
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _favSub = ServiceLocator.instance.db.favoritesEvents().listen((_) {
      _loadFavorites();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _favSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
    final favDocs = await ServiceLocator.instance.db.listFavorites();
    if (!mounted) return;
    setState(() {
      _favIds = favDocs.map((e) => e.id).toSet();
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      _query = value.trim();
      _load();
    });
  }

  Future<void> _toggleFavorite(PdfDocumentModel d) async {
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

  Future<void> _deletePdf(PdfDocumentModel d) async {
    if (_busy) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar PDF'),
        content: Text(
          'Tens a certeza que queres apagar "${d.name}"?\n'
          'Isto remove o ficheiro, as anotações e os áudios associados.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (confirm != true) return;

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
    // amarelo → verde → azul claro (estilo ScrollCast)
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
                    return ListTile(
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
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'library_import_fab',
        onPressed: _busy ? null : _importPdf,
        label: const Text('Importar PDF'),
        icon: const Icon(Icons.file_open),
      ),
    );
  }
}
