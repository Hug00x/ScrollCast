import 'package:firebase_auth/firebase_auth.dart';

String friendlyAuthMessage(Object e, {bool forSignUp = false}) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'wrong-password':
        return 'Email ou password incorretos.';
      case 'user-not-found':
        return 'Conta não encontrada para esse email.';
      case 'invalid-email':
        return 'Email inválido.';
      case 'too-many-requests':
        return 'Muitas tentativas. Por favor tenta novamente mais tarde.';
      case 'weak-password':
        return 'Password demasiado fraca. Usa pelo menos 6 caracteres.';
      case 'email-already-in-use':
        return forSignUp
            ? 'Este email já está em uso. Tenta outro email ou inicia sessão.'
            : 'Este email já está registado. Tenta iniciar sessão.';
      default:
        return 'Ocorreu um erro de autenticação. Por favor tenta novamente.';
    }
  }

  return 'Ocorreu um erro. Por favor tenta novamente.';
}
