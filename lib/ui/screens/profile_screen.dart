import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'onboarding_start_screen.dart';
import '../../main.dart';

/*
  Perfil (profile_screen.dart)

  Visão geral:
  - Este ficheiro contém o ecrã de Perfil da aplicação. Aqui o utilizador pode ver e gerir a sessão ativa,
    trocar entre contas já usadas no dispositivo, alterar/remover avatar local (para contas email/password),
    e aceder a opções de ajuda e ações destrutivas (apagar conta, apagar dados do convidado).

  Propósito:
  - Centralizar toda a lógica relacionada com contas conhecidas neste dispositivo, incluindo
    persistência simples em Hive (box `known_accounts`).
  - Fornecer diálogos e fluxos de reautenticação quando necessário (por exemplo ao apagar conta).
*/

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // === Estado local / boxes ===
  // _box: Hive box que guarda metadados das contas já usadas neste dispositivo.
  // _accounts: lista em memória de contas conhecidas, usada para apresentar opções ao utilizador.
  static const _boxName = 'known_accounts';
  Box? _box;
  List<_KnownAccount> _accounts = [];
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    // Inicializa a lista de contas conhecidas e subscreve alterações na autenticação
    // para manter a UI sincronizada quando o estado do utilizador muda.
    _initAccounts();
    _authSub = FirebaseAuth.instance.userChanges().listen((_) {
      _initAccounts();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _initAccounts() async {
    // Abre a `known_accounts` box do Hive.
    _box = Hive.isBoxOpen(_boxName) ? Hive.box(_boxName) : await Hive.openBox(_boxName);

    // Se houver um utilizador autenticado, garante que existe uma entrada na box
    // com o UID atual (mantendo o caminho do avatar local se já existia).
    final u = FirebaseAuth.instance.currentUser;
    if (u != null) {
      final prev = _box!.get(u.uid);
      final existingPath = (prev is Map && prev['localAvatarPath'] is String)
          ? prev['localAvatarPath'] as String?
          : null;
      final ka = _KnownAccount.fromUser(u).copyWith(localAvatarPath: existingPath);
      await _box!.put(ka.uid, ka.toMap());
    }
    // Carrega todas as contas para memória.
    _loadAccounts();
  }

  void _loadAccounts() {
    // Constrói a lista de `_KnownAccount` a partir da box e ordena para que a
    // conta atual (se existir) apareça primeiro. Caso contrário ordena por último uso.
    if (_box == null) return;
    final items = <_KnownAccount>[];
    for (final k in _box!.keys) {
      final m = Map<String, dynamic>.from(_box!.get(k));
      items.add(_KnownAccount.fromMap(m));
    }
    final current = FirebaseAuth.instance.currentUser?.uid;
    items.sort((a, b) {
      if (a.uid == current) return -1;
      if (b.uid == current) return 1;
      final da = a.lastUsed ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.lastUsed ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
    setState(() => _accounts = items);
  }

  Future<void> _afterAuthIdentityChange({String goTo = OnboardingStartScreen.route}) async {
    // Limpa caches gráficos para evitar que avatares antigos fiquem em cache
    // após uma mudança de conta e depois navega para o ecrã indicado (Onboarding).
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(goTo, (_) => false);
  }

  Future<void> _showErrorDialog(String message, {String title = 'Erro'}) async {
    // Apresenta um AlertDialog simples com uma mensagem de erro.
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _switchToAccount(_KnownAccount acc) async {
    // Troca a sessão para a conta selecionada.
    // Suporta contas Google (login automático) e Email/Password (pede password).
    final auth = FirebaseAuth.instance;
    final prevUid = auth.currentUser?.uid;
    if (prevUid == acc.uid) return;

    try {
      if (acc.isGoogle) {
        // Inicia fluxo Google.
        await ServiceLocator.instance.auth.signInWithGoogle();
      } else {
        // Pede password ao utilizador e efetua signIn com email.
        final pass = await _askPassword(context, acc.email ?? '');
        if (pass == null) return;
        await ServiceLocator.instance.auth.signInWithEmail(acc.email!, pass);
      }

      // Verifica se a troca de UID ocorreu.
      final newUid = FirebaseAuth.instance.currentUser?.uid;
      final success = newUid != null && newUid != prevUid;

      if (!success) {
        // Apresenta feedback consoante o tipo de conta.
        if (!acc.isGoogle) {
          await _showErrorDialog(
            'Password incorreta.',
            title: 'Autenticação falhou',
          );
        } else {
          _snack('Não foi possível entrar com Google.');
        }
        return;
      }

      // Se a troca ocorreu, atualiza a entrada na box com metadados mais recentes.
      final u = auth.currentUser!;
      if (_box != null) {
        final prev = _box!.get(u.uid);
        final existingPath = (prev is Map && prev['localAvatarPath'] is String)
            ? prev['localAvatarPath'] as String?
            : null;
        final ka = _KnownAccount.fromUser(u).copyWith(localAvatarPath: existingPath);
        await _box!.put(ka.uid, ka.toMap());
      }

      // Navega para a raiz da app depois de trocar de conta.
      await _afterAuthIdentityChange(goTo: '/');
    } on FirebaseAuthException catch (e) {
      // Tratamento de erros específicos do Firebase (ex.: password errada).
      final code = e.code;
      if (!acc.isGoogle &&
          (code == 'wrong-password' || code == 'invalid-credential' || code == 'user-not-found')) {
        await _showErrorDialog('Password incorreta.', title: 'Autenticação falhou');
        return; // mantém-se na ProfileScreen.
      } else {
        _snack('Falha ao trocar para ${acc.email ?? acc.displayName}: ${e.message ?? e.code}');
      }
    } catch (e) {
      _snack('Falha ao trocar para ${acc.email ?? acc.displayName}: $e');
    }
  }

  Future<void> _deleteCurrentAccount() async {
    // Apaga a conta atualmente autenticada.
    // - Pede confirmação textual ao utilizador.
    final auth = FirebaseAuth.instance;
    final u = auth.currentUser;
    if (u == null) return;

    final ok = await _confirmDelete(context);
    if (ok != true) return;

    try {
      await u.delete();
      await _box?.delete(u.uid);
      _snack('Conta apagada.');
      await _afterAuthIdentityChange(goTo: OnboardingStartScreen.route);
    } on FirebaseAuthException catch (e) {
      // Alguns endpoints exigem reautenticação recente. Neste caso tentamos reautenticar.
      if (e.code == 'requires-recent-login') {
        final success = await _reauthenticateFlow(u);
        if (success) {
          try {
            await u.delete();
            await _box?.delete(u.uid);
            _snack('Conta apagada.');
            await _afterAuthIdentityChange(goTo: OnboardingStartScreen.route);
          } catch (e2) {
            _snack('Falha ao apagar após reautenticação: $e2');
          }
        }
      } else {
        _snack('Erro ao apagar conta: ${e.message ?? e.code}');
      }
    } catch (e) {
      _snack('Erro ao apagar conta: $e');
    }
  }

  Future<bool> _reauthenticateFlow(User u) async {
    // Faz o fluxo de reautenticação necessário para operações sensíveis (como apagar conta).
    // Para contas Google tenta o sign-in Google; para Email/Password pede a password novamente.
    final isGoogle = u.providerData.any((p) => p.providerId == 'google.com');
    try {
      if (isGoogle) {
        await ServiceLocator.instance.auth.signInWithGoogle();
        return FirebaseAuth.instance.currentUser != null;
      } else {
        final email = u.email ?? '';
        final pass = await _askPassword(context, email, title: 'Reautenticar');
        if (pass == null) return false;
        await ServiceLocator.instance.auth.signInWithEmail(email, pass);
        return true;
      }
    } catch (e) {
      _snack('Reautenticação falhou: $e');
      return false;
    }
  }

  // ================== Avatar local (email/password) ==================

  Future<void> _changeAvatar() async {
    // Permite ao utilizador escolher uma imagem local para usar como avatar (apenas para contas email/password).
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return; //contas Convidado não têm avatar.
    final isGoogle = user.providerData.any((p) => p.providerId == 'google.com');
    if (isGoogle) return; // contas Google usam a foto remota.

    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (xfile == null) return;

    final uid = user.uid;
    final root = await ServiceLocator.instance.storage.appRoot();
    final avatarsDir = Directory(p.join(root, 'avatars'));
    await avatarsDir.create(recursive: true);

    // Remove avatares antigos deste UID para evitar acumulação.
    await _deleteAllAvatarsFor(uid);

    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = p.extension(xfile.path).toLowerCase();
    final destPath = p.join(avatarsDir.path, 'avatar_${uid}_$ts$ext');

    await ServiceLocator.instance.storage.copyFile(xfile.path, destPath);

    // Atualiza a entrada local na box com o caminho do avatar recém-copiado.
    if (_box != null) {
      final prev = _box!.get(uid);
      final m = prev is Map ? Map<String, dynamic>.from(prev) : <String, dynamic>{};
      m['uid'] = uid;
      m['email'] = m['email'] ?? user.email;
      m['displayName'] = m['displayName'] ?? user.displayName;
      m['photoUrl'] = m['photoUrl'] ?? user.photoURL;
      m['isGoogle'] = m['isGoogle'] ?? false;
      m['lastUsed'] = DateTime.now().millisecondsSinceEpoch;
      m['localAvatarPath'] = destPath;
      await _box!.put(uid, m);
      _loadAccounts();
    }

    // Evict cache para garantir que a nova imagem é renderizada.
    try {
      PaintingBinding.instance.imageCache.evict(FileImage(File(destPath)));
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}

    if (mounted) setState(() {});
  }

  Future<void> _removeAvatar() async {
    // Remove o avatar local.
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final isGoogle = user.providerData.any((p) => p.providerId == 'google.com');
    if (isGoogle) return;

    await _deleteAllAvatarsFor(user.uid);
    try {
      await user.updatePhotoURL(null);
    } catch (_) {}

    if (_box != null) {
      final prev = _box!.get(user.uid);
      if (prev is Map) {
        final m = Map<String, dynamic>.from(prev);
        m.remove('localAvatarPath');
        await _box!.put(user.uid, m);
        _loadAccounts();
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> _deleteAllAvatarsFor(String uid) async {
    // Apaga todos os ficheiros de avatar que pertencem ao UID fornecido.
    final root = await ServiceLocator.instance.storage.appRoot();
    final dir = Directory(p.join(root, 'avatars'));
    if (!await dir.exists()) return;

    for (final f in dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('avatar_${uid}_'))) {
      try {
        PaintingBinding.instance.imageCache.evict(FileImage(File(f.path)));
        PaintingBinding.instance.imageCache.clearLiveImages();
      } catch (_) {}
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  // =================== Dialogos/UX ===================

  Future<String?> _askPassword(BuildContext ctx, String email,
      {String title = 'Introduz a password'}) async {
    final c = TextEditingController();
    // Mostra um diálogo que pede a password do utilizador. Retorna a string
    // introduzida ou null se o utilizador cancelar.
    return showDialog<String>(
      context: ctx,
      builder: (dctx) {
        bool obscure = true;
        return StatefulBuilder(
          builder: (_, setSt) => AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(email, style: Theme.of(ctx).textTheme.bodySmall),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: c,
                  autofocus: true,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: obscure ? 'Mostrar' : 'Ocultar',
                      icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setSt(() => obscure = !obscure),
                    ),
                  ),
                  onSubmitted: (_) => Navigator.pop(dctx, c.text),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(dctx, c.text), child: const Text('Entrar')),
            ],
          ),
        );
      },
    );
  }

  Future<bool?> _confirmDelete(BuildContext ctx) async {
    // Diálogo de confirmação que pede ao utilizador que escreva "confirmar"
    // para evitar eliminações acidentais.
    final t = TextEditingController();
  bool matches(String s) => s.trim().toLowerCase() == 'confirmar';

    return showDialog<bool>(
      context: ctx,
      builder: (dctx) => StatefulBuilder(
        builder: (_, setSt) => AlertDialog(
          title: const Text('Apagar conta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Para confirmar, escreve exatamente: confirmar'),
              const SizedBox(height: 8),
              TextField(
                controller: t,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'confirmar',
                ),
                onChanged: (_) => setSt(() {}),
                onSubmitted: (_) {
                  if (matches(t.text)) Navigator.pop(dctx, true);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: matches(t.text) ? () => Navigator.pop(dctx, true) : null,
              child: const Text('Apagar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmClearData(BuildContext ctx) async {
    // Diálogo idêntico a _confirmDelete mas usado para apagar dados do convidado.
    final t = TextEditingController();
  bool matches(String s) => s.trim().toLowerCase() == 'confirmar';

    return showDialog<bool>(
      context: ctx,
      builder: (dctx) => StatefulBuilder(
        builder: (_, setSt) => AlertDialog(
          title: const Text('Apagar dados'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Para confirmar, escreve exatamente: confirmar'),
              const SizedBox(height: 8),
              TextField(
                controller: t,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'confirmar',
                ),
                onChanged: (_) => setSt(() {}),
                onSubmitted: (_) {
                  if (matches(t.text)) Navigator.pop(dctx, true);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: matches(t.text) ? () => Navigator.pop(dctx, true) : null,
              child: const Text('Apagar'),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg) {
    // Mostra uma Snackbar com a mensagem fornecida.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // =================== Ajuda ===================

  Future<void> _openHelp() async {
    final cs = Theme.of(context).colorScheme;
    // Abre um sheet detalhado de Ajuda mostrando secções e linhas explicativas.
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: ListView(
                controller: controller,
                children: [
                  Row(
                    children: [
                      Icon(Icons.help_outline_rounded, color: cs.primary),
                      const SizedBox(width: 8),
                      Text('Ajuda & Guia Rápido', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const SizedBox(height: 12),

                  _HelpSection(
                    icon: Icons.person_outline_rounded,
                    title: 'Este ecrã (Perfil)',
                    children: [
                      _HelpRow(Icons.brightness_6_rounded, 'Tema claro',
              'Alterna entre tema claro e escuro.'),
            _HelpRow(Icons.image_rounded, 'Alterar avatar',
              'Para contas email/password: toca no avatar ou usa "Alterar avatar" para escolher uma foto da galeria. Contas Google e Convidado não podem alterar a foto.'),
                      _HelpRow(Icons.delete_outline_rounded, 'Remover avatar',
                          'Remove a foto de avatar local e volta às iniciais.'),
                      _HelpRow(Icons.swap_horiz_rounded, 'Trocar de conta',
                          'Muda diretamente para outra conta já usada neste dispositivo, sem passar pelo ecrã de autenticação.'),
                      _HelpRow(Icons.logout_rounded, 'Terminar sessão',
                          'Sai da conta atual e volta ao ecrã de entrada.'),
                      _HelpRow(Icons.delete_forever_rounded, 'Apagar conta',
                          'Apaga permanentemente a tua conta. Será pedido que escrevas “confirmar” para evitar acidentes.'),
                    ],
                  ),

                  const SizedBox(height: 16),

                  _HelpSection(
                    icon: Icons.brush_rounded,
                    title: 'Anotações (PDFs e Cadernos)',
                    children: [
                      _HelpRow(Icons.pan_tool_alt, 'Modo Mão',
                          'Arrasta e faz zoom ao documento.'),
                           _HelpRow(Icons.brush_rounded, 'Modo Desenho',
                          'Usa o dedo para desenhar livremente.'),
                      _HelpRow(Icons.create_rounded, 'Modo Caneta',
                          'Se uma caneta for detetada, os dedos servem para arrastar/zoom e a caneta desenha.'),
                      _HelpRow(Icons.auto_fix_off_rounded,'Borracha',
                          'Apaga segmentos do traço ao passar por cima. O tamanho da borracha é configurável.'),
                      _HelpRow(Icons.sticky_note_2_outlined, 'Notas de texto',
                          'Adiciona pinos de texto no documento. Toca para editar; o painel aparece em baixo.'),
                      _HelpRow(Icons.mic_rounded, 'Notas de áudio',
                          'Grava um áudio e fixa um pino na página. Podes mover/apagar.'),
            _HelpRow(Icons.image_outlined, 'Importar imagens',
              'Toca no ícone "Importar imagem" na AppBar para adicionar uma imagem à página; a imagem é guardada localmente.'),
               _HelpRow(Icons.center_focus_strong, 'Repor enquadramento',
                          'Volta o zoom/posição ao estado inicial.'),
            _HelpRow(Icons.open_with, 'Redimensionar e rodar imagens',
              'Seleciona uma imagem e arrasta as pegas nos cantos para redimensionar. Usa a pega de rotação para rodar a imagem.'),
                      _HelpRow(Icons.undo, 'Undo / Redo',
                          'Desfaz/refaz a última ação de desenho.'),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // =================== UI ===================

  @override
  Widget build(BuildContext context) {
    // Estrutura geral:
    //  - AppBar com título
    //  - Lista vertical com: avatar, estado da sessão, opções de tema, ajuda,
    //    ações para avatar (quando aplicável), seleção de conta, terminar sessão e ações destrutivas.

    final theme = ServiceLocator.instance.theme;
    final isLight = theme.value == ThemeMode.light;

    // Estado do utilizador atual (pode ser nulo se não autenticado)
    final User? current = FirebaseAuth.instance.currentUser;
    final currentUid = current?.uid;
    // Detecta se a sessão atual é Google
    final isGoogle = current?.providerData.any((p) => p.providerId == 'google.com') ?? false;
    // Detecta sessão convidado/anonima
    bool isGuest;
    if (current == null) {
      isGuest = true;
    } else {
      isGuest = current.isAnonymous;
    }

    // Outras contas gravadas localmente (exclui a conta atual)
    final others = _accounts.where((a) => a.uid != currentUid).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Avatar central: mostra a imagem do utilizador ou iniciais; permite alterar quando aplicável.
          Center(child: _ProfileAvatar(accountsBox: _box, onTap: (!isGoogle && !isGuest) ? () => _changeAvatar() : null)),
          const SizedBox(height: 16),
          // Rótulo que indica qual a sessão ativa
          Center(child: Text('Sessão ativa', style: Theme.of(context).textTheme.labelMedium)),
          const SizedBox(height: 24),

          // Switch para alternar entre tema claro/escuro — atualiza a app inteira.
          SwitchListTile(
            title: const Text('Tema claro'),
            value: isLight,
            onChanged: (v) => theme.value = v ? ThemeMode.light : ThemeMode.dark,
            secondary: const Icon(Icons.brightness_6_rounded),
          ),

          // Acesso à ajuda/guia rápido.
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: const Text('Ajuda'),
            subtitle: const Text('Como funciona cada botão e ferramenta.'),
            onTap: _openHelp,
          ),

          // Se a conta não é Google nem Guest, mostramos ações locais de avatar (alterar / remover).
          if (!isGoogle && !isGuest) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.image_rounded),
              title: const Text('Alterar avatar'),
              onTap: _changeAvatar,
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Remover avatar'),
              onTap: _removeAvatar,
            ),
          ],

          const Divider(),

          // Trocar de conta: abre um bottom sheet com as contas guardadas. A seleção troca sessão.
          ListTile(
            leading: const Icon(Icons.swap_horiz_rounded),
            title: const Text('Trocar de conta'),
            subtitle: others.isEmpty
                ? const Text('Sem outras contas usadas neste dispositivo.')
                : Text('${others.length} contas disponíveis'),
            onTap: others.isEmpty
                ? null
                : () async {
                    final selected = await showModalBottomSheet<_KnownAccount>(
                      context: context,
                      showDragHandle: true,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      builder: (bctx) {
                        return SafeArea(
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemBuilder: (_, i) {
                              final a = others[i];
                              return ListTile(
                                leading: _AccountAvatar(a: a),
                                title: Text(a.displayName ?? a.email ?? '(sem nome)'),
                                subtitle: Text(a.isGoogle ? 'Google' : 'Email/Password'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.pop(bctx, a),
                              );
                            },
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemCount: others.length,
                          ),
                        );
                      },
                    );
                    if (selected != null) {
                      await _switchToAccount(selected);
                    }
                  },
          ),

          // Terminar sessão: desloga e navega para o ecrã de onboarding/entrada.
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Terminar sessão'),
            onTap: () async {
              await ServiceLocator.instance.auth.signOut();
              await _afterAuthIdentityChange(goTo: OnboardingStartScreen.route);
            },
          ),

          const Divider(),

          // Ações destrutivas: apagar dados do convidado ou apagar conta permanentemente.
          if (isGuest)
            ListTile(
              leading: const Icon(Icons.delete_sweep_rounded),
              title: const Text('Apagar dados'),
              subtitle: const Text('Isto é definitivo.'),
              textColor: Theme.of(context).colorScheme.error,
              iconColor: Theme.of(context).colorScheme.error,
              onTap: () async {
                final ok = await _confirmClearData(context);
                if (ok == true) {
                  await _clearGuestData();
                }
              },
            )
          else
            ListTile(
              leading: const Icon(Icons.delete_forever_rounded),
              title: const Text('Apagar conta'),
              subtitle: const Text('Isto é definitivo.'),
              textColor: Theme.of(context).colorScheme.error,
              iconColor: Theme.of(context).colorScheme.error,
              onTap: _deleteCurrentAccount,
            ),
        ],
      ),
    );
  }

  Future<void> _clearGuestData() async {
    final uid = ServiceLocator.instance.auth.currentUid ?? '_anon';
    final boxes = <String>[
      'pdfs_$uid',
      'annotations_$uid',
      'favorites_$uid',
      'notebooks_$uid',
      'notebook_pages_$uid',
      'nb_favorites_$uid',
      _boxName,
    ];
    for (final name in boxes) {
      try {
        final b = Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);
        if (name == _boxName) {
          await b.delete(uid);
        } else {
          await b.clear();
        }
      } catch (_) {}
    }
    await _deleteAllAvatarsFor(uid);

    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}

    _snack('Dados do convidado limpos.');
    await _afterAuthIdentityChange(goTo: OnboardingStartScreen.route);
  }

  // =================== Utilitários de UI e modelos locais ===================
  // A partir daqui estão pequenos widgets auxiliares e a representação local
  // do modelo de conta (`_KnownAccount`). Estes tipos são usados principalmente
  // para apresentar listas de contas, avatares e para serializar os metadados guardados na box Hive `known_accounts`.
}

class _AccountAvatar extends StatelessWidget {
  final _KnownAccount a;
  const _AccountAvatar({required this.a});

  @override
  Widget build(BuildContext context) {
    if (a.isGoogle) {
      final provider = (a.photoUrl != null && a.photoUrl!.isNotEmpty)
          ? NetworkImage(a.photoUrl!)
          : null;
      return CircleAvatar(
        radius: 18,
        backgroundColor: Theme.of(context).colorScheme.primary.withAlpha((.2 * 255).round()),
        foregroundImage: provider,
        child: provider == null ? Text(_initials(a.displayName ?? a.email ?? '')) : null,
      );
    }

    // Para contas locais (email/password) procuramos um caminho de avatar.
    final path = a.localAvatarPath;
    final provider = (path != null && File(path).existsSync())
        ? FileImage(File(path))
        : null;
    return CircleAvatar(
      radius: 18,
      backgroundColor: Theme.of(context).colorScheme.primary.withAlpha((.2 * 255).round()),
      foregroundImage: provider,
      child: provider == null ? Text(_initials(a.displayName ?? a.email ?? '')) : null,
    );
  }

  String _initials(String s) {
    final t = s.trim();
    if (t.isEmpty) return 'SC';
    final parts = t.split(RegExp(r'\s+'));
    final a = parts[0].isNotEmpty ? parts[0][0].toUpperCase() : 'S';
    final b = (parts.length > 1 && parts[1].isNotEmpty)
        ? parts[1][0].toUpperCase()
        : (parts[0].length > 1 ? parts[0][1].toUpperCase() : 'C');
    return '$a$b';
  }
}

class _ProfileAvatar extends StatelessWidget {
  final Box? accountsBox;
  final VoidCallback? onTap;
  const _ProfileAvatar({required this.accountsBox, this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snap) {
        final user = snap.data ?? FirebaseAuth.instance.currentUser;
        if (user == null) {
          return const CircleAvatar(radius: 44, child: Icon(Icons.person));
        }
        // Constrói o avatar principal mostrado no ecrã de perfil.
        // - Para contas Google usamos a foto remota (se disponível).
        // - Para contas locais procuramos um `localAvatarPath` na box `known_accounts`.
        // - Em ausência de imagem mostramos as iniciais.
        final isGoogle = user.providerData.any((p) => p.providerId == 'google.com');
        if (isGoogle) {
          final url = user.photoURL;
          final provider = (url != null && url.isNotEmpty) ? NetworkImage(url) : null;
          final avatar = CircleAvatar(
            radius: 44,
            backgroundColor: Theme.of(context).colorScheme.primary.withAlpha((.2 * 255).round()),
            foregroundImage: provider,
            child: provider == null ? Text(_initials(user.displayName ?? user.email ?? '')) : null,
          );
          return avatar;
        }

        // Se existe uma entrada local na box com um caminho para avatar, usa-o.
        String? path;
        final map = accountsBox?.get(user.uid);
        if (map is Map && map['localAvatarPath'] is String) {
          path = map['localAvatarPath'] as String;
        }
        final provider = (path != null && File(path).existsSync())
            ? FileImage(File(path))
            : null;
        final avatar = CircleAvatar(
          radius: 44,
          backgroundColor: Theme.of(context).colorScheme.primary.withAlpha((.2 * 255).round()),
          foregroundImage: provider,
          child: provider == null ? Text(_initials(user.displayName ?? user.email ?? '')) : null,
        );
        // Se for possível alterar avatar, tornamos o widget clicável.
        if (onTap != null) {
          return GestureDetector(onTap: onTap, child: avatar);
        }
        return avatar;
      },
    );
  }

  static String _initials(String s) {
    final t = s.trim();
    if (t.isEmpty) return 'SC';
    final parts = t.split(RegExp(r'\s+'));
    final a = parts[0].isNotEmpty ? parts[0][0].toUpperCase() : 'S';
    final b = (parts.length > 1 && parts[1].isNotEmpty)
        ? parts[1][0].toUpperCase()
        : (parts[0].length > 1 ? parts[0][1].toUpperCase() : 'C');
    return '$a$b';
  }
}

class _KnownAccount {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String? localAvatarPath;
  final bool isGoogle;
  final DateTime? lastUsed;

  _KnownAccount({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.localAvatarPath,
    required this.isGoogle,
    this.lastUsed,
  });

  _KnownAccount copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    String? localAvatarPath,
    bool? isGoogle,
    DateTime? lastUsed,
  }) =>
      _KnownAccount(
        uid: uid ?? this.uid,
        email: email ?? this.email,
        displayName: displayName ?? this.displayName,
        photoUrl: photoUrl ?? this.photoUrl,
        localAvatarPath: localAvatarPath ?? this.localAvatarPath,
        isGoogle: isGoogle ?? this.isGoogle,
        lastUsed: lastUsed ?? this.lastUsed,
      );

  factory _KnownAccount.fromUser(User u) => _KnownAccount(
        uid: u.uid,
        email: u.email,
        displayName: u.displayName,
        photoUrl: u.photoURL,
        localAvatarPath: null,
        isGoogle: u.providerData.any((p) => p.providerId == 'google.com'),
        lastUsed: DateTime.now(),
      );

  // Serialização para armazenamento na `Hive` box `known_accounts`.
  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'localAvatarPath': localAvatarPath,
        'isGoogle': isGoogle,
        'lastUsed': (lastUsed ?? DateTime.now()).millisecondsSinceEpoch,
      };

  factory _KnownAccount.fromMap(Map<String, dynamic> m) => _KnownAccount(
        uid: m['uid'] as String,
        email: m['email'] as String?,
        displayName: m['displayName'] as String?,
        photoUrl: m['photoUrl'] as String?,
        localAvatarPath: m['localAvatarPath'] as String?,
        isGoogle: (m['isGoogle'] as bool?) ?? false,
        lastUsed: m['lastUsed'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['lastUsed'] as int)
            : null,
      );
}

class _HelpSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  const _HelpSection({required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Painel estilizado usado no sheet de Ajuda; encapsula um ExpansionTile
    // com um background levemente destacado para separar secções visuais.
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha((0.35 * 255).round()),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        // Expandido por omissão para que o utilizador veja o conteúdo rapidamente.
        initiallyExpanded: true,
        leading: Icon(icon, color: cs.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: children,
      ),
    );
  }
}

class _HelpRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  const _HelpRow(this.icon, this.title, this.desc);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ícone de secção e texto descritivo.
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: [
                  TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: desc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
