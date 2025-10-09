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

  // Favoritos em memória + sub de eventos
  Set<String> _favIds = <String>{};
  StreamSubscription<void>? _favSub;

  @override
  void initState() {
    super.initState();
    _load();
    // ouvir alterações a favoritos vindas de qualquer sítio da app
    _favSub = ServiceLocator.instance.db.favoritesEvents().listen((_) {
      _loadFavorites(); // atualização imediata
    });
  }

  @override
  void dispose() {
    _favSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final docs = await ServiceLocator.instance.db.listPdfs();
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
      final newPath =
          await storage.createUniqueFilePath(destDir, extension: 'pdf');
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apagar')),
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
    return Scaffold(
      // 🔥 Logout removido — agora vive na aba Perfil
      appBar: AppBar(title: const Text('A minha biblioteca')),
      body: Stack(
        children: [
          _items.isEmpty
              ? const Center(
                  child: Text('Sem PDFs ainda. Toca em "Importar PDF".'),
                )
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = _items[i];
                    final isFav = _favIds.contains(d.id);
                    return ListTile(
                      leading: GestureDetector(
                        onTap: () => _toggleFavorite(d),
                        child: isFav
                            ? ShaderMask(
                                shaderCallback: _titleGradient,
                                blendMode: BlendMode.srcIn,
                                child: const Icon(Icons.star, size: 22),
                              )
                            : const Icon(Icons.star_border,
                                size: 22, color: Colors.white24),
                      ),
                      title: ShaderMask(
                        shaderCallback: _titleGradient,
                        blendMode: BlendMode.srcIn,
                        child: Text(
                          d.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
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
                            onPressed: _busy ? null : () => _deletePdf(d),
                            icon: Image.asset(
                              'assets/icon_delete.png',
                              width: 24,
                              height: 24,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.delete, size: 24),
                            ),
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
        onPressed: _busy ? null : _importPdf,
        label: const Text('Importar PDF'),
        icon: const Icon(Icons.file_open),
      ),
    );
  }
}
