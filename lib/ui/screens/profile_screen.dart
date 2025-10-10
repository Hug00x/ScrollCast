import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../main.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _boxName = 'known_accounts';
  Box? _box;
  List<_KnownAccount> _accounts = [];
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
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
    _box = Hive.isBoxOpen(_boxName) ? Hive.box(_boxName) : await Hive.openBox(_boxName);

    final u = FirebaseAuth.instance.currentUser;
    if (u != null) {
      // preserva localAvatarPath existente
      final prev = _box!.get(u.uid);
      final existingPath = (prev is Map && prev['localAvatarPath'] is String) ? prev['localAvatarPath'] as String? : null;
      final ka = _KnownAccount.fromUser(u).copyWith(localAvatarPath: existingPath);
      await _box!.put(ka.uid, ka.toMap());
    }

    _loadAccounts();
  }

  void _loadAccounts() {
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

  Future<void> _switchToAccount(_KnownAccount acc) async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser?.uid == acc.uid) return;

    try {
      if (acc.isGoogle) {
        await ServiceLocator.instance.auth.signInWithGoogle();
      } else {
        final pass = await _askPassword(context, acc.email ?? '');
        if (pass == null) return;
        await ServiceLocator.instance.auth.signInWithEmail(acc.email!, pass);
      }

      final u = auth.currentUser;
      if (u != null && _box != null) {
        final prev = _box!.get(u.uid);
        final existingPath = (prev is Map && prev['localAvatarPath'] is String) ? prev['localAvatarPath'] as String? : null;
        final ka = _KnownAccount.fromUser(u).copyWith(localAvatarPath: existingPath);
        await _box!.put(ka.uid, ka.toMap());
        _loadAccounts();
      }
      if (mounted) setState(() {});
    } catch (e) {
      _snack('Falha ao trocar para ${acc.email ?? acc.displayName}: $e');
    }
  }

  Future<void> _deleteCurrentAccount() async {
    final auth = FirebaseAuth.instance;
    final u = auth.currentUser;
    if (u == null) return;

    final ok = await _confirmDelete(context);
    if (ok != true) return;

    try {
      await u.delete();
      await _box?.delete(u.uid);
      _snack('Conta apagada.');
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/signin', (_) => false);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        final success = await _reauthenticateFlow(u);
        if (success) {
          try {
            await u.delete();
            await _box?.delete(u.uid);
            _snack('Conta apagada.');
            if (mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil('/signin', (_) => false);
            }
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

  // ========= Avatar (guarda caminho absoluto em known_accounts) =========

  Future<void> _changeAvatar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final isGoogle = user.providerData.any((p) => p.providerId == 'google.com');
    if (isGoogle) return;

    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (xfile == null) return;

    final uid = user.uid;

    // diretório global da app (não dependente do utilizador)
    final root = await ServiceLocator.instance.storage.appRoot();
    final avatarsDir = Directory(p.join(root, 'avatars')); // continua a ser o mesmo, mas usamos caminho ABS
    await avatarsDir.create(recursive: true);

    // apaga anteriores + evict cache
    await _deleteAllAvatarsFor(uid);

    // nome com timestamp para bust de cache
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = p.extension(xfile.path).toLowerCase();
    final destPath = p.join(avatarsDir.path, 'avatar_${uid}_$ts$ext');

    await ServiceLocator.instance.storage.copyFile(xfile.path, destPath);

    // guarda caminho absoluto na box
    if (_box != null) {
      final prev = _box!.get(uid);
      final m = prev is Map ? Map<String, dynamic>.from(prev) : <String, dynamic>{};
      m['uid'] = uid;
      m['email'] = m['email'] ?? user.email;
      m['displayName'] = m['displayName'] ?? user.displayName;
      m['photoUrl'] = m['photoUrl'] ?? user.photoURL;
      m['isGoogle'] = m['isGoogle'] ?? false;
      m['lastUsed'] = DateTime.now().millisecondsSinceEpoch;
      m['localAvatarPath'] = destPath; // <- chave nova
      await _box!.put(uid, m);
      _loadAccounts();
    }

    if (mounted) setState(() {});
  }

  Future<void> _removeAvatar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final isGoogle = user.providerData.any((p) => p.providerId == 'google.com');
    if (isGoogle) return;

    await _deleteAllAvatarsFor(user.uid);
    try {
      await user.updatePhotoURL(null);
    } catch (_) {}

    // limpa caminho guardado
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
    final root = await ServiceLocator.instance.storage.appRoot();
    final dir = Directory(p.join(root, 'avatars'));
    if (!await dir.exists()) return;

    for (final f in dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('avatar_${uid}_'))) {
      _evictFileFromCache(f.path);
      await f.delete().catchError((_) {});
    }
  }

  void _evictFileFromCache(String path) {
    try {
      final provider = FileImage(File(path));
      // ignore: deprecated_member_use
      PaintingBinding.instance.imageCache.evict(provider);
      // ignore: deprecated_member_use
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}
  }

  // =================== Dialogs/UX ===================

  Future<String?> _askPassword(BuildContext ctx, String email, {String title = 'Introduz a password'}) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(alignment: Alignment.centerLeft, child: Text(email, style: Theme.of(ctx).textTheme.bodySmall)),
            const SizedBox(height: 8),
            TextField(
              controller: c,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
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
  }

  Future<bool?> _confirmDelete(BuildContext ctx) async {
    final t = TextEditingController();
    bool _matches(String s) => s.trim().toLowerCase() == 'confirmar';

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
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'confirmar'),
                onChanged: (_) => setSt(() {}),
                onSubmitted: (_) {
                  if (_matches(t.text)) Navigator.pop(dctx, true);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: _matches(t.text) ? () => Navigator.pop(dctx, true) : null, child: const Text('Apagar')),
          ],
        ),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // =================== UI ===================

  @override
  Widget build(BuildContext context) {
    final theme = ServiceLocator.instance.theme;
    final isLight = theme.value == ThemeMode.light;

    final current = FirebaseAuth.instance.currentUser;
    final currentUid = current?.uid;
    final isGoogle = current?.providerData.any((p) => p.providerId == 'google.com') ?? false;

    final others = _accounts.where((a) => a.uid != currentUid).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: _ProfileAvatar(accountsBox: _box)),

          const SizedBox(height: 16),
          Center(child: Text('Sessão ativa', style: Theme.of(context).textTheme.labelMedium)),
          const SizedBox(height: 24),

          SwitchListTile(
            title: const Text('Tema claro'),
            value: isLight,
            onChanged: (v) => theme.value = v ? ThemeMode.light : ThemeMode.dark,
            secondary: const Icon(Icons.brightness_6_rounded),
          ),

          if (!isGoogle) ...[
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
                            separatorBuilder: (_, __) => const Divider(height: 1),
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

          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Terminar sessão'),
            onTap: () async {
              await ServiceLocator.instance.auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/signin', (_) => false);
              }
            },
          ),

          const Divider(),

          ListTile(
            leading: const Icon(Icons.delete_forever_rounded),
            title: const Text('Apagar conta'),
            subtitle: const Text('Isto é definitivo. Vai pedir confirmação.'),
            textColor: Theme.of(context).colorScheme.error,
            iconColor: Theme.of(context).colorScheme.error,
            onTap: _deleteCurrentAccount,
          ),
        ],
      ),
    );
  }
}

// =================== Avatares ===================

class _AccountAvatar extends StatelessWidget {
  final _KnownAccount a;
  const _AccountAvatar({required this.a});

  @override
  Widget build(BuildContext context) {
    if (a.isGoogle) {
      final provider = (a.photoUrl != null && a.photoUrl!.isNotEmpty) ? NetworkImage(a.photoUrl!) : null;
      return CircleAvatar(
        radius: 18,
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(.2),
        foregroundImage: provider,
        child: provider == null ? Text(_initials(a.displayName ?? a.email ?? '')) : null,
      );
    }

    final path = a.localAvatarPath;
    final provider = (path != null && File(path).existsSync()) ? FileImage(File(path)) : null;
    return CircleAvatar(
      radius: 18,
      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(.2),
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
  const _ProfileAvatar({required this.accountsBox});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snap) {
        final user = snap.data ?? FirebaseAuth.instance.currentUser;
        if (user == null) {
          return const CircleAvatar(radius: 44, child: Icon(Icons.person));
        }
        final isGoogle = user.providerData.any((p) => p.providerId == 'google.com');
        if (isGoogle) {
          final url = user.photoURL;
          final provider = (url != null && url.isNotEmpty) ? NetworkImage(url) : null;
          return CircleAvatar(
            radius: 44,
            backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(.2),
            foregroundImage: provider,
            child: provider == null ? Text(_initials(user.displayName ?? user.email ?? '')) : null,
          );
        }

        // email/password → usa caminho guardado na box
        String? path;
        final map = accountsBox?.get(user.uid);
        if (map is Map && map['localAvatarPath'] is String) {
          path = map['localAvatarPath'] as String;
        }
        final provider = (path != null && File(path).existsSync()) ? FileImage(File(path)) : null;
        return CircleAvatar(
          radius: 44,
          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(.2),
          foregroundImage: provider,
          child: provider == null ? Text(_initials(user.displayName ?? user.email ?? '')) : null,
        );
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

// =================== Modelo ===================

class _KnownAccount {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;        // Google
  final String? localAvatarPath; // caminho absoluto para avatar local (email/password)
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
        localAvatarPath: m['localAvatarPath'] as String?, // pode ser null em registos antigos
        isGoogle: (m['isGoogle'] as bool?) ?? false,
        lastUsed: m['lastUsed'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['lastUsed'] as int)
            : null,
      );
}
