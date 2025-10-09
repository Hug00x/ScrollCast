import 'package:flutter/material.dart';
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
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(.2),
              child: const Icon(Icons.person_rounded, size: 44),
            ),
          ),
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
