// lib/ui/screens/notebooks_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../main.dart';
import '../../models/notebook_model.dart';
import 'notebook_viewer_screen.dart';

class NotebooksScreen extends StatefulWidget {
  const NotebooksScreen({super.key});
  @override
  State<NotebooksScreen> createState() => _NotebooksScreenState();
}

class _NotebooksScreenState extends State<NotebooksScreen> {
  String? _folder; // filtro atual (null = raiz/"Sem Pasta")
  List<String> _folders = [];
  List<NotebookModel> _items = [];
  bool _busy = false;

  // ===== Favoritos de caderno (Hive local) =====
  Box? _favBox;
  Set<String> _favIds = <String>{};
  StreamSubscription<BoxEvent>? _favWatchSub;
  String get _favBoxName =>
      'nb_favorites_${ServiceLocator.instance.auth.currentUid ?? "_anon"}';

  @override
  void initState() {
    super.initState();
    _initFavs().then((_) => _reload());
  }

  Future<void> _initFavs() async {
    _favBox = Hive.isBoxOpen(_favBoxName)
        ? Hive.box(_favBoxName)
        : await Hive.openBox(_favBoxName);
    _pullFavIds();

    // Rebuild sempre que houver mudanças na box
    _favWatchSub?.cancel();
    _favWatchSub = _favBox!.watch().listen((_) {
      _pullFavIds();
      if (mounted) setState(() {});
    });
  }

  void _pullFavIds() {
    _favIds = _favBox?.keys.whereType<String>().toSet() ?? <String>{};
  }

  Future<void> _reload() async {
    final db = ServiceLocator.instance.db;

    List<NotebookModel> items;
    if (_folder == null) {
      items = await db.listNotebooks();
      items = items
          .where((n) => n.folder == null || n.folder!.isEmpty)
          .toList();
    } else {
      items = await db.listNotebooks(folder: _folder);
    }
    items.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));

    final folders = await db.listNotebookFolders();
    if (!mounted) return;
    setState(() {
      _items = items;
      _folders = folders;
    });
  }

  Future<void> _newNotebook() async {
    final nameCtrl = TextEditingController();
    final folderCtrl = TextEditingController(text: _folder ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo caderno'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nome')),
            TextField(controller: folderCtrl, decoration: const InputDecoration(labelText: 'Pasta (opcional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Criar')),
        ],
      ),
    );
    if (ok != true) return;

    final id = const Uuid().v4();
    final nb = NotebookModel(
      id: id,
      name: nameCtrl.text.trim().isEmpty ? 'Caderno' : nameCtrl.text.trim(),
      folder: folderCtrl.text.trim().isEmpty ? null : folderCtrl.text.trim(),
      pageCount: 1,
      lastOpened: DateTime.now(),
      lastPage: 0,
    );

    await ServiceLocator.instance.db.upsertNotebook(nb);
    await _reload();

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotebookViewerScreen(
          args: NotebookViewerArgs(notebookId: nb.id, name: nb.name),
        ),
      ),
    ).then((_) => _reload());
  }

  Future<void> _deleteNotebook(NotebookModel n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar caderno'),
        content: Text( 'Tens a certeza que queres apagar "${n.name}"?\n'
          'Isto remove o caderno, as anotações e os áudios associados.',),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    await _favBox?.delete(n.id); // remove também dos favoritos
    await ServiceLocator.instance.db.deleteNotebook(n.id);
    await _reload();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggleFavorite(NotebookModel n) async {
    if (_favBox == null) return;
    final isFav = _favIds.contains(n.id);
    if (isFav) {
      await _favBox!.delete(n.id);
    } else {
      await _favBox!.put(n.id, true);
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
  void dispose() {
    _favWatchSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
  final Color unfavColor = cs.onSurfaceVariant.withAlpha((0.55 * 255).round());

    final chips = <Widget>[
      ChoiceChip(
        label: const Text('Sem Pasta'),
        selected: _folder == null,
        onSelected: (_) => setState(() {
          _folder = null;
          _reload();
        }),
      ),
      for (final f in _folders)
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: ChoiceChip(
            label: Text(f),
            selected: _folder == f,
            onSelected: (_) => setState(() {
              _folder = f;
              _reload();
            }),
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Cadernos')),
      body: Stack(
        children: [
          Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: chips),
              ),
              Expanded(
                child: _items.isEmpty
                    ? const Center(child: Text('Sem cadernos. Toca em "Novo caderno".'))
          : ListView.separated(
            itemCount: _items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final n = _items[i];
                          final isFav = _favIds.contains(n.id);
                          return ListTile(
                            leading: InkResponse(
                              onTap: () => _toggleFavorite(n),
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
                              ).then((_) => _reload());
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Apagar',
                                  onPressed: () => _deleteNotebook(n),
                                  icon: const Icon(Icons.delete_outline_rounded),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Color(0x33000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'notebooks_new_fab',
        onPressed: _newNotebook,
        icon: const Icon(Icons.note_add_rounded),
        label: const Text('Novo caderno'),
      ),
    );
  }
}
