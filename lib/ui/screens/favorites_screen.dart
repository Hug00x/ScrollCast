import 'dart:async';
import 'package:flutter/material.dart';
import '../../main.dart';
import '../../models/pdf_document_model.dart';
import 'pdf_viewer_screen.dart';

class FavoriteScreen extends StatefulWidget {
  const FavoriteScreen({super.key});
  @override
  State<FavoriteScreen> createState() => _FavoriteScreenState();
}

class _FavoriteScreenState extends State<FavoriteScreen> {
  final _db = ServiceLocator.instance.db;
  List<PdfDocumentModel> _items = [];
  bool _busy = false;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    // 🔔 recarrega sempre que favoritos mudam (em qualquer parte da app)
    _sub = _db.favoritesEvents().listen((_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await _db.listFavorites();
    items.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    if (mounted) setState(() => _items = items);
  }

  Shader _titleGradient(Rect bounds) {
    return const LinearGradient(
      colors: [
        Color(0xFFFFC107), // amber
        Color(0xFF4CAF50), // green
        Color(0xFF26C6DA), // light teal/blue
      ],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    ).createShader(bounds);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favoritos')),
      body: _items.isEmpty
          ? const Center(child: Text('Ainda não tens favoritos.'))
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final d = _items[i];
                return ListTile(
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  subtitle: Text('${d.pageCount} páginas'),
                  onTap: () => Navigator.pushNamed(
                    context,
                    PdfViewerScreen.route,
                    arguments: PdfViewerArgs(pdfId: d.id, name: d.name, path: d.originalPath),
                  ).then((_) => _load()),
                  trailing: IconButton(
                    tooltip: 'Remover dos favoritos',
                    icon: const Icon(Icons.star),
                    onPressed: () async {
                      await _db.setFavorite(d.id, false); // _load() virá pelo stream
                    },
                  ),
                );
              },
            ),
    );
  }
}
