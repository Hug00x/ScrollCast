import 'package:firebase_auth/firebase_auth.dart';
//Lança quando uma autenticação tipo Google corresponde a uma conta existente.
class AccountExistsWithDifferentCredential implements Exception {
  final String? email;
  final AuthCredential pendingCredential;
  AccountExistsWithDifferentCredential(this.email, this.pendingCredential);
  @override
  String toString() => 'AccountExistsWithDifferentCredential($email)';
}
//Interface abstrata para serviço de autenticação.
abstract class AuthService {

  //Lança mudanças no estado de autenticação do utilizador
  Stream<String?> authStateChanges();

  //AAutentica o utilizador com email e password
  Future<void> signInWithEmail(String email, String pass);

  //Regista um novo utlizador com email e password
  Future<void> signUpWithEmail(String email, String pass);

  //Autentica o utilizador com Google Sign-In
  Future<void> signInWithGoogle();

  //Termina a sessão do utilizador atual
  Future<void> signOut();
  String? get currentUid;
}
