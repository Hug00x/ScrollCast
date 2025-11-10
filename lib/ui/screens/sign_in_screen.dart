import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../main.dart';
import '../auth_error_messages.dart';
import '../../services/auth_service.dart' show AccountExistsWithDifferentCredential;
import 'dart:async';
import 'home_shell.dart';

/*
  sign_in_screen.dart

  Propósito geral:
  - Este ficheiro implementa a tela de entrada/autenticação da aplicação.
  - Fornece campos para email/password, botão para entrar e botão para
    autenticação com Google. Trata fluxos especiais como "account-exists-with-different-credential"
    mostrando um diálogo para solicitar a password do utilizador existente e, se fornecida,
    liga (link) a credencial Google ao utilizador.
  - O widget usa um StatefulWidget para gerir estado local: indicadores de busy, visibilidade
    da password e mensagens de erro. O método build inclui os widgets visuais (inputs,
    botões e diálogos). Mantemos a construção limitada a uma largura máxima para uma boa
    aparência em ecrãs largos.

  Organização do ficheiro:
  - O ficheiro deliberadamente utiliza o BuildContext através de uma chamada await quando
    mostra um diálogo (ver _doGoogle). Isso normalmente dispara o lint
    `use_build_context_synchronously`. O fluxo está protegido por verificações de `mounted`
    logo após as operações assíncronas para prevenir usos inválidos do contexto.
  - Navegação para a tela principal (`HomeShell`) é feita com `pushAndRemoveUntil` após
    autenticação bem-sucedida para remover o histórico de navegação.
*/

class SignInScreen extends StatefulWidget {
  static const route = '/signin';
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  /*
    Controladores de texto para os campos de email e password.
    Mantemos o ciclo de vida e descartamos no dispose().
  */
  final _email = TextEditingController();
  final _pass = TextEditingController();

  /*
    Estado local simples:
    - _busy: indica operação em curso.
    - _showPass: controla se a password está visível.
    - _error: mensagem de erro a apresentar ao utilizador.
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
    // Remove o foco dos campos de texto quando o utilizador inicia uma ação.
    final f = FocusScope.of(context);
    if (!f.hasPrimaryFocus && f.focusedChild != null) f.unfocus();
  }

  void _goHomeIfLogged() {
    /*
      Navega para o ecrã principal se houver um utilizador autenticado.
      Usamos pushAndRemoveUntil para limpar a pilha e evitar que o utilizador
      volte para o ecrã de login com o botão atrás.
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
      Consulta segura dos métodos de login associados a um email.
      - Retorna lista vazia em caso de email inválido ou erro de rede.
      - Usada para detectar se a conta é Google e assim apresentar
        uma mensagem apropriada ao utilizador.
    */
    if (email.isEmpty || !email.contains('@')) return const <String>[];
    try {
      return await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _doSignIn() async {
    /*
      Handler para o botão de autenticação por email/password.

      Fluxo:
      - Remove foco dos inputs
      - Seta _busy para true para desativar UI.
      - Verifica se a conta está ligada ao Google.
      - Chama o serviço de autenticação e, em caso de sucesso, navega para Home.
      - Em caso de erro, traduz a exceção para uma mensagem adequada.
      - Garante reset de _busy no finally.
    */
    _unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      final email = _email.text.trim();
      final pass = _pass.text.trim();

      final methods = await _safeFetchMethods(email);
      if (methods.contains('google.com')) {
        //Se conta já existe e usa Google, orienta o utilizador para o fluxo correto.
        setState(() => _error = 'Esta conta entra com Google. Usa "Continuar com Google".');
        return;
      }

      await ServiceLocator.instance.auth.signInWithEmail(email, pass);
  if (!mounted) return; // proteger uso de BuildContext após await
  _goHomeIfLogged(); // navega para o ecrã principal
    } catch (e) {
      // Se a autenticação interna não criou uma sessão, mostramos erro.
      if (ServiceLocator.instance.auth.currentUid == null) {
        if (!mounted) return;
        setState(() => _error = friendlyAuthMessage(e));
      } else {
        if (!mounted) return;
        _goHomeIfLogged();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doGoogle() async {
    /*
      Handler para autenticação com Google.

      Fluxo normal:
      - Chama o serviço de autenticação Google.
      - Em sucesso, navega para Home.

      Fluxo especial (AccountExistsWithDifferentCredential):
      - Ocorre quando há uma conta existente com o mesmo email mas diferente
        método de autenticação (email/password). Nesse caso pede ao
        utilizador a password da conta existente através de um diálogo.
      - Se o utilizador fornecer a password e o login por email for bem sucedido,
        ligamos a credencial pendente do Google ao utilizador (linkWithCredential).
    */
    _unfocus();
    setState(() { _busy = true; _error = null; });
    try {
  await ServiceLocator.instance.auth.signInWithGoogle();
  if (!mounted) return;
  _goHomeIfLogged(); // navega para o ecrã principal
    } catch (e) {
      // Tratar fluxo especial onde a conta já existe com outro método
      if (e is AccountExistsWithDifferentCredential) {
        final email = e.email;
        final pending = e.pendingCredential;

        // Mostrar diálogo que pede a password da conta existente para que possa
        // autenticar e depois ligar a credencial Google pendente.
        final pass = await showDialog<String>(
          context: context,
          builder: (ctx) {
            final tc = TextEditingController();
            return AlertDialog(
              title: const Text('Conta já existe'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(email == null ? 'Esta conta já existe.' : 'Já existe uma conta para $email. Introduz a password para a ligar.'),
                  const SizedBox(height: 8),
                  TextField(controller: tc, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                FilledButton(onPressed: () => Navigator.pop(ctx, tc.text.trim()), child: const Text('Entrar e ligar')),
              ],
            );
          },
        );

        if (!mounted) return; // proteger uso do contexto após await

        if (pass != null && pass.isNotEmpty) {
          try {
            // Tentar autenticar com email/password e então ligar a credencial Google.
            await ServiceLocator.instance.auth.signInWithEmail(email ?? '', pass);
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              await user.linkWithCredential(pending);
            }
            if (!mounted) return;
            _goHomeIfLogged();
            return;
          } catch (linkErr) {
            if (!mounted) return;
            setState(() => _error = friendlyAuthMessage(linkErr));
            return;
          }
        }

        // Utilizador cancelou ou não forneceu password.
        setState(() => _error = 'Operação cancelada.');
        return;
      }

      // Erro genérico: traduzir para mensagem amigável se não há sessão
      if (ServiceLocator.instance.auth.currentUid == null) {
        setState(() => _error = friendlyAuthMessage(e));
      } else {
        _goHomeIfLogged();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + kb),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    /*
                      Cabeçalho visual (logotipo) e inputs.
                      - Container estilizado com imagem da aplicação.
                      - Campos de email e password.
                      - O campo password tem um botão suffix para mostrar/esconder.
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

                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pass,
                      obscureText: !_showPass,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _busy ? null : _doSignIn(),
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

                    // Mensagem de erro (se existir) apresentada ao utilizador
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(_error!, style: TextStyle(color: cs.error), textAlign: TextAlign.center),
                      ),

                    // Botão principal: Entrar com email/password
                    FilledButton(
                      onPressed: _busy ? null : _doSignIn,
                      child: _busy
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Entrar'),
                    ),
                    const SizedBox(height: 8),

                    // Botão secundário: autenticacão com Google
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _doGoogle,
                      icon: const Icon(Icons.g_mobiledata, size: 28),
                      label: const Text('Continuar com Google'),
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
