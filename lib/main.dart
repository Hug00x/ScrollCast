import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';

import 'services/pdf_service.dart';
import 'services/audio_service.dart';
import 'services/storage_service.dart';
import 'services/database_service.dart';
import 'services/pdf_service_impl.dart';
import 'services/audio_service_impl.dart';
import 'services/storage_service_impl.dart';
import 'services/database_service_impl.dart';
import 'services/auth_service.dart';
import 'services/auth_service_firebase.dart';

import 'ui/app_theme.dart';
import 'ui/screens/sign_in_screen.dart';
import 'ui/screens/library_screen.dart';
import 'ui/screens/pdf_viewer_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // <-- Firebase
  await Hive.initFlutter();

  ServiceLocator.instance
    ..auth = AuthServiceFirebase()
    ..pdf = PdfServiceImpl()
    ..audio = AudioServiceImpl()
    ..storage = StorageServiceImpl()
    ..db = DatabaseServiceImpl();

  runApp(const PdfNotesApp());
}

class ServiceLocator {
  static final instance = ServiceLocator._();
  ServiceLocator._();

  late AuthService auth;
  late PdfService pdf;
  late AudioService audio;
  late StorageService storage;
  late DatabaseService db;
}

class PdfNotesApp extends StatelessWidget {
  const PdfNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = buildAppTheme();
    return MaterialApp(
      title: 'ScrollCast',
      theme: theme,
      debugShowCheckedModeBanner: false,

      // Mantemos o "home" com o decisor de root (login vs biblioteca)
      home: const _RootDecider(),

      // PARA EVITAR O ASSERT: não usamos o `routes:` map.
      // Em vez disso, resolvemos as rotas aqui:
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case SignInScreen.route:
            return MaterialPageRoute(builder: (_) => const SignInScreen());
          case LibraryScreen.route:
            return MaterialPageRoute(builder: (_) => const LibraryScreen());
          case PdfViewerScreen.route:
            final args = settings.arguments as PdfViewerArgs;
            return MaterialPageRoute(builder: (_) => PdfViewerScreen(args: args));
          default:
            // fallback: vai para a biblioteca (ou SignIn se preferires)
            return MaterialPageRoute(builder: (_) => const LibraryScreen());
        }
      },
    );
  }
}

class _RootDecider extends StatelessWidget {
  const _RootDecider({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = ServiceLocator.instance.auth;
    return StreamBuilder<String?>(
      stream: auth.authStateChanges(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.active) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final uid = snap.data;
        if (uid == null) return const SignInScreen();
        return const LibraryScreen();
      },
    );
  }
}
