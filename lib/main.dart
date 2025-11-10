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

// main.dart
// Propósito geral:
// - Este é o ponto de entrada da aplicação Flutter. Inicializa serviços
//   globais necessários (Firebase, Hive) e configura o `ServiceLocator` com
//   implementações concretas dos serviços usados pela app (auth, pdf, audio,
//   storage, database e tema).
// - Define o widget raíz (`PdfNotesApp`) que lê o `ThemeMode` partilhado e
//   fornece a navegação (rotas) e o `home` inicial que decide se o utilizador
//   está autenticado ou deve ver o onboarding.
//
// Observações de design:
// - O ServiceLocator é usado aqui para injetar dependências sem recorrer
//   a frameworks mais complexos. Os serviços são instanciados no
//   `main` para garantir que estão prontos antes de `runApp`.
// - O ThemeMode é persistido usando Hive numa box `prefs`.


Future<void> main() async {
  // Necessário para inicializações assíncronas ligadas ao Flutter.
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar Firebase (serviços cloud) e Hive (persistência local).
  await Firebase.initializeApp();
  await Hive.initFlutter();

  // Abrir a box de preferências onde guardamos o ThemeMode do utilizador.
  final prefs = await Hive.openBox('prefs');

  // Configurar o ServiceLocator com as implementações concretas usadas pela app.
  ServiceLocator.instance
    ..auth    = AuthServiceFirebase()
    ..pdf     = PdfServiceImpl()
    ..audio   = AudioServiceImpl()
    ..storage = StorageServiceImpl()
    ..db      = DatabaseServiceImpl()
    ..theme   = ValueNotifier<ThemeMode>(
      // Recuperar preferência de tema; por omissão usamos dark.
      (prefs.get('themeMode') as String?) == 'light'
          ? ThemeMode.light
          : ThemeMode.dark,
    );

  // Re-guardar preferência quando o ThemeMode for alterado durante runtime.
  ServiceLocator.instance.theme.addListener(() {
    prefs.put(
      'themeMode',
      ServiceLocator.instance.theme.value == ThemeMode.light ? 'light' : 'dark',
    );
  });

  // Iniciar a app depois de todas as inicializações.
  runApp(const PdfNotesApp());
}


// Simple ServiceLocator singleton para registar serviços globais.
class ServiceLocator {
  static final instance = ServiceLocator._();
  ServiceLocator._();

  // Serviços expostos pela app. São inicializados em `main()`.
  late AuthService auth;
  late PdfService pdf;
  late AudioService audio;
  late StorageService storage;
  late DatabaseService db;

  // Notifier partilhado para o ThemeMode da app.
  late ValueNotifier<ThemeMode> theme;
}


// Widget raiz da aplicação.
class PdfNotesApp extends StatelessWidget {
  const PdfNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    // O ValueListenableBuilder reconstrói o MaterialApp sempre que o ThemeMode
    // muda, permitindo alternância dinâmica entre temas claro/escuro.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ServiceLocator.instance.theme,
      builder: (_, mode, child) {
        return MaterialApp(
          title: 'ScrollCast',
          theme: buildLightAppTheme(),   // tema claro
          darkTheme: buildAppTheme(),    // tema escuro 
          themeMode: mode,
          debugShowCheckedModeBanner: false,
          home: const _RootDecider(),
          // onGenerateRoute centraliza a criação das rotas nomeadas usadas pela app.
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
                // PdfViewer espera argumentos (PdfViewerArgs) quando é aberto.
                final args = settings.arguments as PdfViewerArgs;
                return MaterialPageRoute(builder: (_) => PdfViewerScreen(args: args));
              default:
                // Rota por omissão: abrir a HomeShell (aba Biblioteca).
                return MaterialPageRoute(builder: (_) => const HomeShell(initialIndex: 1));
            }
          },
        );
      },
    );
  }
}


/// Decide qual ecrã inicial mostrar com base no estado de autenticação.
///
/// - Enquanto o stream de autenticação ainda não está ativo mostra um loader.
/// - Se não houver utilizador autenticado mostra o onboarding.
/// - Se houver um user autenticado abre a Home (aba Biblioteca).
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
        // Se não há uid, o utilizador não está autenticado -> onboarding.
        final uid = snap.data;
        if (uid == null) return const OnboardingStartScreen();
        // Utilizador autenticado: abrir Home na aba Biblioteca (index 1).
        return const HomeShell(initialIndex: 1);
      },
    );
  }
}
