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
import 'ui/screens/home_shell.dart';        
import 'ui/screens/sign_up_screen.dart';
import 'ui/screens/onboarding_start_screen.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await Hive.initFlutter();

  // prefs (para guardar o ThemeMode)
  final prefs = await Hive.openBox('prefs');

  ServiceLocator.instance
    ..auth    = AuthServiceFirebase()
    ..pdf     = PdfServiceImpl()
    ..audio   = AudioServiceImpl()
    ..storage = StorageServiceImpl()
    ..db      = DatabaseServiceImpl()
    ..theme   = ValueNotifier<ThemeMode>(
      (prefs.get('themeMode') as String?) == 'light'
          ? ThemeMode.light
          : ThemeMode.dark,
    );

  // re-guardar quando muda
  ServiceLocator.instance.theme.addListener(() {
    prefs.put(
      'themeMode',
      ServiceLocator.instance.theme.value == ThemeMode.light ? 'light' : 'dark',
    );
  });

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

  // <-- NOVO
  late ValueNotifier<ThemeMode> theme;
}

class PdfNotesApp extends StatelessWidget {
  const PdfNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ServiceLocator.instance.theme,
  builder: (_, mode, child) {
        return MaterialApp(
          title: 'ScrollCast',
          theme: buildLightAppTheme(),   // claro
          darkTheme: buildAppTheme(),    // escuro (o teu atual)
          themeMode: mode,
          debugShowCheckedModeBanner: false,
          home: const _RootDecider(),
          onGenerateRoute: (settings) {
            switch (settings.name) {
              case OnboardingStartScreen.route:
                return MaterialPageRoute(builder: (_) => const OnboardingStartScreen());
              case SignInScreen.route:
                return MaterialPageRoute(builder: (_) => const SignInScreen());
              case SignUpScreen.route:
                return MaterialPageRoute(builder: (_) => const SignUpScreen());
              case LibraryScreen.route:
                return MaterialPageRoute(builder: (_) => const LibraryScreen());
              case PdfViewerScreen.route:
                final args = settings.arguments as PdfViewerArgs;
                return MaterialPageRoute(builder: (_) => PdfViewerScreen(args: args));
              default:
                return MaterialPageRoute(builder: (_) => const HomeShell(initialIndex: 1));
            }
          },
        );
      },
    );
  }
}

class _RootDecider extends StatelessWidget {
  const _RootDecider();
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
        if (uid == null) return const OnboardingStartScreen();
        // Abre Home com a aba 1 = Biblioteca
        return const HomeShell(initialIndex: 1);
      },
    );
  }
}
