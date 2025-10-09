import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../main.dart';
import '../../models/pdf_document_model.dart';
import 'pdf_viewer_screen.dart';

/// Store simples para favoritos (por utilizador) em Hive.
class FavoritesStore {
  FavoritesStore(this.uid);
  final String uid;

  String get _boxName => 'favorites_$uid';

  Future<Box> _open() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return Hive.openBox(_boxName);
  }

  Future<Set<String>> _getAll() async {
    final box = await _open();
    final list = (box.get('pdfs') as List?)?.cast<String>() ?? const <String>[];
    return list.toSet();
  }

  Future<bool> isFav(String id) async => (await _getAll()).contains(id);

  Future<void> toggle(String id) async {
    final box = await _open();
    final all = await _getAll(); // Set<String>
    if (!all.add(id)) all.remove(id); // adiciona ou remove
    await box.put('pdfs', all.toList());
  }

  Future<Set<String>> ids() => _getAll();
}

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});
  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late final FavoritesStore _store =
      FavoritesStore(ServiceLocator.instance.auth.currentUid ?? '_anon');

  List<PdfDocumentModel> _items = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final favIds = await _store.ids();
    final all = await ServiceLocator.instance.db.listPdfs();
    final favs = all.where((d) => favIds.contains(d.id)).toList()
      ..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    setState(() {
      _items = favs;
      _busy = false;
    });
  }

  Shader _titleGradient(Rect bounds) => const LinearGradient(
        colors: [Color(0xFFFFC107), Color(0xFF4CAF50), Color(0xFF26C6DA)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(bounds);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favoritos')),
      body: Stack(
        children: [
          _items.isEmpty
              ? const Center(child: Text('Sem favoritos ainda.'))
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = _items[i];
                    return ListTile(
                      leading: const Icon(Icons.star_rounded, color: Color(0xFFFFD64D)),
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
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          PdfViewerScreen.route,
                          arguments: PdfViewerArgs(pdfId: d.id, name: d.name, path: d.originalPath),
                        ).then((_) => _load());
                      },
                      trailing: IconButton(
                        tooltip: 'Remover dos favoritos',
                        onPressed: () async {
                          await _store.toggle(d.id);
                          await _load();
                        },
                        icon: const Icon(Icons.star_outline_rounded),
                      ),
                    );
                  },
                ),
          if (_busy)
            const PositionedFillBusy(),
        ],
      ),
    );
  }
}

class PositionedFillBusy extends StatelessWidget {
  const PositionedFillBusy({super.key});
  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: Color(0x33000000),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}
