import 'package:firebase_auth/firebase_auth.dart';

/// Thrown when a federated sign-in (e.g. Google) matches an existing
/// account that uses a different sign-in method (typically email/password).
class AccountExistsWithDifferentCredential implements Exception {
  final String? email;
  final AuthCredential pendingCredential;
  AccountExistsWithDifferentCredential(this.email, this.pendingCredential);
  @override
  String toString() => 'AccountExistsWithDifferentCredential($email)';
}

abstract class AuthService {
  Stream<String?> authStateChanges();
  Future<void> signInWithEmail(String email, String pass);
  Future<void> signUpWithEmail(String email, String pass);
  Future<void> signInWithGoogle();
  Future<void> signOut();
  String? get currentUid;
}
