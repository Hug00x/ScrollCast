import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../main.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ServiceLocator.instance.theme;
    final isLight = theme.value == ThemeMode.light;

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: _ProfileAvatar()), // ⬅️ avatar dinâmico (Google photoURL ou iniciais)
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Sessão ativa',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            title: const Text('Tema claro'),
            value: isLight,
            onChanged: (v) => theme.value = v ? ThemeMode.light : ThemeMode.dark,
            secondary: const Icon(Icons.brightness_6_rounded),
          ),
          const Divider(),
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
        ],
      ),
    );
  }
}

/// Avatar que mostra a foto da conta Google (se existir) ou cai para iniciais.
class _ProfileAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      // reage a mudanças de utilizador (login/logout, refresh de token, etc.)
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snap) {
        final user = snap.data ?? FirebaseAuth.instance.currentUser;
        final photoUrl = user?.photoURL;
        final isGoogle = user?.providerData.any((p) => p.providerId == 'google.com') ?? false;
        final initials = _initials(user?.displayName ?? user?.email ?? '');

        return CircleAvatar(
          radius: 44, // mantém o tamanho que tinhas
          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(.2),
          // se login Google e houver foto, usa-a
          foregroundImage: (isGoogle && photoUrl != null && photoUrl.isNotEmpty)
              ? NetworkImage(photoUrl)
              : null,
          // fallback: iniciais
          child: (isGoogle && photoUrl != null && photoUrl.isNotEmpty)
              ? null
              : Text(
                  initials,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
                ),
        );
      },
    );
  }

  String _initials(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return 'SC';
    final parts = trimmed.split(RegExp(r'\s+'));
    String first = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0][0].toUpperCase() : 'S';
    String second;
    if (parts.length > 1 && parts[1].isNotEmpty) {
      second = parts[1][0].toUpperCase();
    } else {
      second = parts[0].length > 1 ? parts[0][1].toUpperCase() : 'C';
    }
    return '$first$second';
  }
}
