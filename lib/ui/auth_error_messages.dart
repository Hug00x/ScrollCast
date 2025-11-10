import 'package:firebase_auth/firebase_auth.dart';

// ---------------------------------------------------------------------------
// auth_error_messages.dart
//
// Propósito geral:
// Este ficheiro contém uma pequena função utilitária que transforma erros
// relacionados com autenticação (especificamente `FirebaseAuthException`) em
// mensagens de texto amigáveis ao utilizador, em Português. A intenção é ter
// um único local onde manter a tradução/normalização desses códigos de erro
// para mostrar na UI (snackbars, diálogos, labels etc.).

String friendlyAuthMessage(Object e, {bool forSignUp = false}) {
  // Se é uma exceção conhecida do Firebase, fazemos o mapeamento por código.
  if (e is FirebaseAuthException) {
    // O `code` do Firebase identifica o tipo de problema; mapeamos para uma
    // mensagem clara em Português.
    switch (e.code) {
      // Password errada para o email indicado.
      case 'wrong-password':
        return 'Email ou password incorretos.';

      // Não existe conta associada ao email.
      case 'user-not-found':
        return 'Conta não encontrada para esse email.';

      // O formato do email é inválido.
      case 'invalid-email':
        return 'Email inválido.';

      // Muitas tentativas em pouco tempo.
      case 'too-many-requests':
        return 'Muitas tentativas. Por favor tenta novamente mais tarde.';

      // Password considerada fraca pelo provider (Menos de 6 caracteres).
      case 'weak-password':
        return 'Password demasiado fraca. Usa pelo menos 6 caracteres.';

      // Email já em uso por outra conta. Mensagem ligeiramente diferente
      // quando o fluxo corrente é de sign-up.
      case 'email-already-in-use':
        return forSignUp
            ? 'Este email já está em uso. Tenta outro email ou inicia sessão.'
            : 'Este email já está registado. Tenta iniciar sessão.';

      // Caso não tenhamos um mapeamento específico, devolvemos uma mensagem
      // genérica relativa à autenticação.
      default:
        return 'Ocorreu um erro de autenticação. Por favor tenta novamente.';
    }
  }

  // Para erros genéricos (não-Firebase) devolvemos uma mensagem de fallback.
  return 'Ocorreu um erro. Por favor tenta novamente.';
}
