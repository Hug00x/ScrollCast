import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../main.dart';
import '../auth_error_messages.dart';
import 'home_shell.dart';

/*
  sign_up_screen.dart

  Propósito geral:
  - Implementa o ecrã de criação de conta da aplicação.
  - Permite ao utilizador criar conta com email/password. Antes de tentar
    criar a conta, valida se o email já está associado a um método Google e
    informa o utilizador para usar o fluxo correto no ecrã de login.
  - Usa um StatefulWidget para gerir estado local (carregamento, visibilidade
    da password e mensagens de erro).
  Organização do ficheiro:
  - O fluxo de criação usa `ServiceLocator.instance.auth.signUpWithEmail`.
  - Após signup bem-sucedido, o utilizador é direcionado para `HomeShell` com
    `pushAndRemoveUntil` para limpar a pilha de navegação.
*/

class SignUpScreen extends StatefulWidget {
  static const route = '/signup';
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  /*
    Controladores dos campos de texto (email e password). Descartados no dispose.
  */
  final _email = TextEditingController();
  final _pass = TextEditingController();

  /*
    Estado local:
    - _busy: operação em curso.
    - _showPass: alterna visibilidade da password.
    - _error: mensagem a apresentar ao utilizador em caso de erro.
  */
  bool _busy = false;
  bool _showPass = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _unfocus() {
    // Remove o foco dos campos quando uma ação é iniciada.
    final f = FocusScope.of(context);
    if (!f.hasPrimaryFocus && f.focusedChild != null) f.unfocus();
  }

  void _goHomeIfLogged() {
    /*
      Navega para o ecrã principal se já existe uma sessão de utilizador.
      Utilizamos pushAndRemoveUntil para garantir que o utilizador não possa
      voltar ao ecrã de criação de conta com o botão "back".
    */
    final uid = ServiceLocator.instance.auth.currentUid;
    if (uid != null && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell(initialIndex: 1)),
        (_) => false,
      );
    }
  }

  Future<List<String>> _safeFetchMethods(String email) async {
    /*
      Consulta segura dos métodos de autenticação associados ao email.
      - Retorna lista vazia para emails inválidos ou em caso de erro.
      - Usada para detectar se o email já pertence a uma conta Google.
    */
    if (email.isEmpty || !email.contains('@')) return const <String>[];
    try {
      return await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _doSignUp() async {
    /*
      Handler do botão "Criar conta".

      Fluxo:
      - Remove foco dos inputs.
      - Seta _busy = true para desativar UI.
      - Verifica se o email está ligado a Google e informa o utilizador.
      - Tenta criar a conta através do serviço de autenticação.
      - Em sucesso, navega para o ecrã principal.
      - Em erro, apresenta mensagem ao utilizador (friendlyAuthMessage).
      - Garante reset de _busy no finally.
    */
    _unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      final email = _email.text.trim();
      final pass = _pass.text.trim();

      final methods = await _safeFetchMethods(email);
      if (methods.contains('google.com')) {
        // Se o email já estiver associado a Google, orienta para o fluxo correto.
        setState(() => _error = 'Este email já está associado a uma conta Google. Usa "Continuar com Google" no ecrã de entrada.');
        return;
      }

      await ServiceLocator.instance.auth.signUpWithEmail(email, pass);
      _goHomeIfLogged();
    } catch (e) {
      if (ServiceLocator.instance.auth.currentUid == null) {
        setState(() => _error = friendlyAuthMessage(e, forSignUp: true));
      } else {
        _goHomeIfLogged();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ColorScheme e altura do teclado para ajustar padding
    final cs = Theme.of(context).colorScheme;
    final kb = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(),
      body: SafeArea(
        child: MediaQuery.removeViewInsets(
          removeBottom: true,
          context: context,
          child: Center(
            child: ConstrainedBox(
              // Limitar largura para uma boa apresentação em ecrãs largos
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + kb),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    /*
                      Cabeçalho visual com logótipo da aplicação.
                      Mantemos a caixa com acabamento para consistência visual.
                    */
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F2230),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24)],
                      ),
                      child: Image.asset('assets/scrollcast_with_name.png', width: 200, height: 200),
                    ),
                    const SizedBox(height: 24),

                    // Campo de email
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),

                    // Campo de password com toggle de visibilidade
                    TextField(
                      controller: _pass,
                      obscureText: !_showPass,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _busy ? null : _doSignUp(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          tooltip: _showPass ? 'Esconder' : 'Mostrar',
                          onPressed: () => setState(() => _showPass = !_showPass),
                          icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Mensagem de erro, se existir
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(_error!, style: TextStyle(color: cs.error), textAlign: TextAlign.center),
                      ),

                    // Botão para criar conta
                    FilledButton(
                      onPressed: _busy ? null : _doSignUp,
                      child: _busy
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Criar conta'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
