import 'dart:async';
import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_service.dart';

class AuthServiceFirebase implements AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Mantém os scopes que já tinhas
  final GoogleSignIn _google = GoogleSignIn(
    scopes: const <String>['email', 'profile'],
  );

  // Timeout anti-“pendura” para todas as operações remotas
  static const Duration _opTimeout = Duration(seconds: 20);

  @override
  Stream<String?> authStateChanges() =>
      _auth.authStateChanges().map((u) => u?.uid);

  @override
  String? get currentUid => _auth.currentUser?.uid;

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

  @override
  Future<void> signInWithGoogle() async {
    try {
      // 🔧 limpar estado antes de abrir o picker evita pickers “presos”
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
              // There's an existing email/password account — let the caller
              // handle linking instead of letting Firebase create a separate
              // account.
              throw AccountExistsWithDifferentCredential(email, cred);
            }
          } catch (e) {
            // Ignore errors fetching methods — we'll still try sign-in and
            // rely on Firebase to report account-exists-with-different-credential
            // if needed.
            developer.log('signInWithGoogle: warning while fetching methods for $email: $e', name: 'auth', level: 900);
          }
        }

        await _auth.signInWithCredential(cred).timeout(_opTimeout);
      } on FirebaseAuthException catch (e) {
        // If the email already exists with a different credential (e.g. the
        // user previously signed up with email/password), surface a specific
        // exception so the UI can offer to link the accounts.
        if (e.code == 'account-exists-with-different-credential') {
          // account.email should be available from the Google account
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

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await _google.signOut();
      await _google.disconnect();
    } catch (_) {
      // ok se não houver sessão Google ativa
    }
  }
}
