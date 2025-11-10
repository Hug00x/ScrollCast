import 'package:flutter/material.dart';
import 'library_screen.dart';
import 'favorites_screen.dart';
import 'notebooks_screen.dart';
import 'profile_screen.dart';

/*
  HomeShell

  Propósito geral:
  - Componente principal que embala as quatro abas principais da aplicação
    (Favoritos, Biblioteca de PDFs, Cadernos e Perfil).
  - Mantém o índice selecionado e expõe a navegação inferior (NavigationBar).
  - Usa um IndexedStack para preservar o estado dos ecrãs ao mudar de aba.

  Organização do ficheiro:
  - `HomeShell` é um StatefulWidget que permite definir uma aba inicial.
  - `_HomeShellState` guarda o índice atual, a lista de páginas e implementa
    a UI (IndexedStack + NavigationBar).

  Nota: este ficheiro centra-se apenas em layout/navegação de topo; a
  responsabilidade de cada ecrã (LibraryScreen, FavoriteScreen, etc.) permanece
  nos respetivos ficheiros.
*/

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialIndex = 1});
  final int initialIndex;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  // Índice da aba atualmente selecionada.
  // `late` porque é inicializado em initState usando `widget.initialIndex`.
  late int _index;

  @override
  void initState() {
    super.initState();
    // Inicializa o índice com o valor opcional passado pelo construtor.
    _index = widget.initialIndex;
  }

  // Lista imutável de páginas que o shell apresenta. Usamos `const` para
  // garantir que os widgets filhos sejam instanciados apenas uma vez e que o
  // IndexedStack consiga preservar o estado de cada ecrã.
  final _pages = const <Widget>[
    FavoriteScreen(),
    LibraryScreen(),
    NotebooksScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ===== Build: Scaffold com IndexedStack + NavigationBar =====
    // - O body usa um IndexedStack para manter o estado interno dos filhos
    //   quando o utilizador muda de aba (por exemplo, scroll position).
    // - A NavigationBar controla qual página está visível, alterando
    //   `_index` via setState.
    return Scaffold(
      // IndexedStack: apenas a criança no índice `_index` é visível, mas
      // todas as crianças permanecem montadas (estado preservado).
      body: IndexedStack(index: _index, children: _pages),
      // Barra de navegação inferior: mapeia cada destino para uma página.
      bottomNavigationBar: NavigationBar(
        // Índice selecionado reflete o estado local.
        selectedIndex: _index,
        // Ao seleccionar um destino, atualizamos `_index` para trocar a aba.
        onDestinationSelected: (i) => setState(() => _index = i),
        // Indicador levemente colorido para realçar a aba ativa.
        indicatorColor: cs.primary.withAlpha((0.15 * 255).round()),
        // Destinations: ícones e rótulos correspondentes às páginas.
        destinations: const [
          NavigationDestination(icon: Icon(Icons.star_border_rounded), selectedIcon: Icon(Icons.star_rounded), label: 'Favoritos'),
          NavigationDestination(icon: Icon(Icons.folder_copy_outlined), selectedIcon: Icon(Icons.folder_copy), label: 'PDFs'),
          NavigationDestination(icon: Icon(Icons.auto_stories_outlined), selectedIcon: Icon(Icons.auto_stories), label: 'Cadernos'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Perfil'),
        ],
      ),
    );
  }
}
