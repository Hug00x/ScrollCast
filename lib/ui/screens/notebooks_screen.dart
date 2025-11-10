import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../main.dart';
import '../../models/notebook_model.dart';
import 'notebook_viewer_screen.dart';

/*
  NotebooksScreen

  Propósito geral:
  - Lista os cadernos do utilizador, permite filtrar por pasta, criar
    novos cadernos, marcar favoritos e apagar cadernos existentes.
  - Mantém um pequeno armazenamento local (Hive) para favoritos e usa o
  - DatabaseService (via ServiceLocator) para listar/criar/apagar cadernos.

  Organização do ficheiro:
  - `NotebooksScreen`: widget com estado que gere a UI de listagem e os
    fluxos de criação/apagamento.
  - Usa uma box Hive por utilizador para guardar IDs favoritos.
*/

// ===== NotebooksScreen (widget) =====
// Widget que apresenta a lista de cadernos do utilizador, filtros por
// pasta, e acções para criar/apagar/abrir cadernos.
class NotebooksScreen extends StatefulWidget {
  const NotebooksScreen({super.key});
  @override
  State<NotebooksScreen> createState() => _NotebooksScreenState();
}

class _NotebooksScreenState extends State<NotebooksScreen> {
  // ===== Estado principal =====
  // `_folder`: pasta selecionada (null = raiz("Sem Pasta")).
  // `_folders`: lista de pastas disponíveis. `_items`: cadernos carregados.
  // `_busy`: indica que uma operação longa está em curso (mostrado overlay).
  String? _folder; // filtro atual (null = raiz/"Sem Pasta")
  List<String> _folders = [];
  List<NotebookModel> _items = [];
  bool _busy = false;

  // ===== Favoritos de caderno (Hive local) =====
  // Usamos uma box por utilizador para guardar IDs de favoritos.
  Box? _favBox;
  Set<String> _favIds = <String>{};
  StreamSubscription<BoxEvent>? _favWatchSub;
  String get _favBoxName =>
      'nb_favorites_${ServiceLocator.instance.auth.currentUid ?? "_anon"}';

  @override
  void initState() {
    super.initState();
    // Inicialização do widget: abre a box de favoritos e carrega a lista
    // de cadernos quando pronta. 
    _initFavs().then((_) => _reload());
  }

  // Abre (ou obtém) a box Hive usada para favoritos e regista um watcher
  // que reconstrói a UI quando a box muda. Também popula o set `_favIds` a partir das chaves.
  Future<void> _initFavs() async {
    _favBox = Hive.isBoxOpen(_favBoxName)
        ? Hive.box(_favBoxName)
        : await Hive.openBox(_favBoxName);
    _pullFavIds();

    _favWatchSub?.cancel();
    _favWatchSub = _favBox!.watch().listen((_) {
      _pullFavIds();
      if (mounted) setState(() {});
    });
  }

  // Extrai as chaves da box de favoritos e atualiza o Set `_favIds` para consultas rápidas na UI.
  void _pullFavIds() {
    _favIds = _favBox?.keys.whereType<String>().toSet() ?? <String>{};
  }

  // Recarrega a lista de cadernos a partir do serviço de base de dados,
  // aplicando o filtro de pasta atual. Atualiza também a lista de pastas
  // disponíveis e ordena por `lastOpened` (mais recentes primeiro).
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

  // Mostra um diálogo para criar um novo caderno; se confirmado cria o
  // `NotebookModel`, persiste-o e navega para o `NotebookViewerScreen`.
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

  // Mostra uma confirmação e, se aceite, apaga o caderno (incluindo
  // anotações, notas, áudios e imagens associadas). Remove também o ID da box de
  // favoritos local e recarrega a lista.
  Future<void> _deleteNotebook(NotebookModel n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar caderno'),
        content: Text( 'Tens a certeza que queres apagar "${n.name}"?\n'
          'Isto remove o caderno, as anotações, notas, áudios e imagens associadas.',),
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
    await _reload(); //recarrega lista após apagar
    if (mounted) setState(() => _busy = false);
  }

  // Alterna o estado de favorito local para o caderno `n` gravando ou
  // removendo a chave na box Hive. A UI é atualizada via watcher da box.
  Future<void> _toggleFavorite(NotebookModel n) async {
    if (_favBox == null) return;
    final isFav = _favIds.contains(n.id);
    if (isFav) {
      await _favBox!.delete(n.id);
    } else {
      await _favBox!.put(n.id, true);
    }
  }

  // Gera um shader de gradiente usado no título dos itens para um visual
  // mais vibrante quando favoritos ou no título principal.
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
    // Cancela a subscrição da box de favoritos e limpa recursos.
    _favWatchSub?.cancel();
    super.dispose();
  }

  @override
  // Monta a árvore da UI: chips de filtro no topo, lista de cadernos
  // no corpo e um FAB para criar novos cadernos. Inclui um overlay de
  // carregamento enquanto `_busy` está ativo.
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
  final Color unfavColor = cs.onSurfaceVariant.withAlpha((0.55 * 255).round());
  // ----- Chips de filtro de pasta -----
  // Linha de chips horizontais que permite ao utilizador filtrar a
  // lista por pasta. Inclui a opção 'Sem Pasta' para ver itens sem
  // pasta atribuída.
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
                          // ----- Item de caderno -----
                          // Cada célula apresenta: ícone de favorito (toggle),
                          // título com gradiente, subtítulo com meta-info (número de páginas),
                          // tap para abrir e ações (apagar).
                          return ListTile(
                            //Leading: ícone de favorito que permite toggle
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
                            // Title: aplica um gradiente e limita o texto a uma linha.
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
                            // Subtitle: mostra contagem de páginas e a pasta onde o caderno se encontra.
                            subtitle: Text('${n.pageCount} páginas • ${n.folder ?? "raiz"}'),
                            // onTap: abre o visualizador do caderno. Ao  regressar do visualizador
                            // recarrega a lista para refletir alterações feitas.
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
                            // Trailing: ações rápidas (apagar + chevron (apenas indicador visual)).
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
          // Overlay de carregamento.
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
      // Botão flutuante para criar novo caderno
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'notebooks_new_fab',
        onPressed: _newNotebook,
        icon: const Icon(Icons.note_add_rounded),
        label: const Text('Novo caderno'),
      ),
    );
  }
}
