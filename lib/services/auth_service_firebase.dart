import 'dart:async';
import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'auth_service.dart';

// auth_service_firebase.dart
//
// Propósito geral:
// - Implementação do `AuthService` usando Firebase Authentication e
//   Google Sign-In. Encapsula operações de autenticação (email/password e
//   Google) e normaliza erros e timeouts.
// - Fornece um stream simples de mudanças de autenticação (`authStateChanges`)
//   que devolve o `uid` do utilizador ou `null` quando não autenticado.
//
// Notas de implementação:
// - Aplica um timeout global `_opTimeout` às operações remotas para evitar
//   chamadas penduradas; quando ocorre timeout a função verifica se o
//   utilizador acabou por ficar autenticado e, nesse caso, considera a
//   operação como bem-sucedida.
// - Antes de iniciar o fluxo de Google Sign-In tentamos limpar qualquer
//   estado anterior do picker para evitar popups “presos”.
// - Para o caso comum de existir uma conta por email/password com o mesmo
//   email, fazemos uma verificação preventiva (`fetchSignInMethodsForEmail`) e
//   lançamos `AccountExistsWithDifferentCredential` para que a camada UI
//   ofereça a opção de ligar credenciais em vez de criar uma nova conta.

class AuthServiceFirebase implements AuthService {
  // Instância do FirebaseAuth usada para todas as operações.
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Cliente Google Sign-In configurado com scopes básicos (email/profile).
  final GoogleSignIn _google = GoogleSignIn(
    scopes: const <String>['email', 'profile'],
  );

  // Timeout anti-“pendura” para todas as operações remotas.
  static const Duration _opTimeout = Duration(seconds: 20);

  /// Stream que mapeia mudanças de sessão do Firebase para o uid do user.
  @override
  Stream<String?> authStateChanges() =>
      _auth.authStateChanges().map((u) => u?.uid);

  /// Obtém o uid do utilizador atualmente autenticado (ou null).
  @override
  String? get currentUid => _auth.currentUser?.uid;

  /// Autentica usando email/password.
  /// - Aplica timeout e trata casos onde a operação timeouts mas o plugin
  ///   conseguiu autenticar o utilizador (tratamos como sucesso nesses casos).
  @override
  Future<void> signInWithEmail(String email, String pass) async {
    try {
      await _auth
          .signInWithEmailAndPassword(email: email, password: pass)
          .timeout(_opTimeout);
    } on TimeoutException {
      // Se o plugin “engoliu” mas o user ficou autenticado, tratamos como sucesso.
      if (_auth.currentUser != null) return;
      rethrow;
    } catch (e) {
      if (_auth.currentUser != null) return;
      rethrow;
    }
  }

  /// Regista um novo utilizador com email/password.
  @override
  Future<void> signUpWithEmail(String email, String pass) async {
    try {
      await _auth
          .createUserWithEmailAndPassword(email: email, password: pass)
          .timeout(_opTimeout);
    } on TimeoutException {
      if (_auth.currentUser != null) return;
      rethrow;
    } catch (e) {
      if (_auth.currentUser != null) return;
      rethrow;
    }
  }

  /// Fluxo de autenticação com Google Sign-In.
  ///
  /// Passos principais:
  /// - Limpar estado do cliente Google para evitar pickers presos.
  /// - Iniciar o fluxo do Google Sign-In e obter tokens.
  /// - Criar credencial e, defensivamente, verificar se já existe uma conta
  ///   por email/password para esse email (neste caso lançamos uma
  ///   `AccountExistsWithDifferentCredential` para que a UI possa ligar as
  ///   contas em vez de criar uma nova).
  /// - Efetuar sign-in com a credencial.
  @override
  Future<void> signInWithGoogle() async {
    try {
      // Limpar estado antes de abrir o picker evita pickers “presos”.
      try {
        await _google.signOut();
        await _google.disconnect();
      } catch (_) {}

      final account = await _google.signIn().timeout(_opTimeout);
      if (account == null) {
        throw Exception('Operação cancelada');
      }

      final gAuth = await account.authentication.timeout(_opTimeout);
      final cred = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );

      // Defensive pre-check: fetch existing sign-in methods for this email
      // to avoid surprising cases where Firebase might create a new user.
      try {
        final email = account.email;
        if (email.isNotEmpty) {
          try {
            final methods = await _auth.fetchSignInMethodsForEmail(email).timeout(_opTimeout);
            // Debug log to help diagnose duplication issues during testing.
            // You can remove these prints in production.
            developer.log('signInWithGoogle: fetched sign-in methods for $email -> $methods', name: 'auth');

            if (methods.contains('password')) {
              // Existe conta com email/password — propagar uma exceção para
              // que a UI possa apresentar opção de ligar as contas.
              throw AccountExistsWithDifferentCredential(email, cred);
            }
          } catch (e) {
            // Ignorar erros a obter métodos; continuamos e deixamos o
            // Firebase reportar account-exists-with-different-credential se
            // necessário.
            developer.log('signInWithGoogle: warning while fetching methods for $email: $e', name: 'auth', level: 900);
          }
        }

        await _auth.signInWithCredential(cred).timeout(_opTimeout);
      } on FirebaseAuthException catch (e) {
        // Se o email já existe com credencial diferente (ex.: email/password),
        // transformamos para uma exceção específica para a UI lidar com link.
        if (e.code == 'account-exists-with-different-credential') {
          throw AccountExistsWithDifferentCredential(account.email, cred);
        }
        rethrow;
      }
    } on TimeoutException {
      if (_auth.currentUser != null) return;
      rethrow;
    } catch (e) {
      if (_auth.currentUser != null) return;
      rethrow;
    }
  }

  /// Faz sign out de Firebase e, se necessário, da sessão Google.
  @override
  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await _google.signOut();
      await _google.disconnect();
    } catch (_) {
    }
  }
}
