// lib/ui/screens/notebooks_screen.dart
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final db = ServiceLocator.instance.db;

    // ✅ Se _folder == null, mostra APENAS cadernos da raiz.
    // Caso contrário, mostra só os da pasta selecionada.
    List<NotebookModel> items;
    if (_folder == null) {
      items = await db.listNotebooks(); // todos…
      items = items
          .where((n) => n.folder == null || n.folder!.isEmpty)
          .toList(); // …filtrados para raiz
    } else {
      items = await db.listNotebooks(folder: _folder);
    }
    items.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));

    final folders = await db.listNotebookFolders();
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
      pageCount: 1, // começa com 1 página vazia
      lastOpened: DateTime.now(),
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
        content: Text('Apagar "${n.name}" e todas as páginas?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    await ServiceLocator.instance.db.deleteNotebook(n.id);
    await _reload();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
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
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final n = _items[i];
                          return ListTile(
                            leading: const Icon(Icons.book_rounded),
                            title: Text(n.name, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                            trailing: IconButton(
                              tooltip: 'Apagar',
                              onPressed: () => _deleteNotebook(n),
                              icon: const Icon(Icons.delete_outline_rounded),
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
        onPressed: _newNotebook,
        icon: const Icon(Icons.note_add_rounded),
        label: const Text('Novo caderno'),
      ),
    );
  }
}
