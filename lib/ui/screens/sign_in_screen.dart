import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../main.dart';
import 'sign_up_screen.dart';

class SignInScreen extends StatefulWidget {
  static const route = '/signin';
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
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
    final f = FocusScope.of(context);
    if (!f.hasPrimaryFocus && f.focusedChild != null) f.unfocus();
  }

  Future<List<String>> _safeFetchMethods(String email) async {
    if (email.isEmpty || !email.contains('@')) return const <String>[];
    try {
      return await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _doSignIn() async {
    _unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      final email = _email.text.trim();
      final pass = _pass.text.trim();

      final methods = await _safeFetchMethods(email);
      if (methods.contains('google.com')) {
        setState(() => _error = 'Esta conta entra com Google. Usa "Continuar com Google".');
        return;
      }

      await ServiceLocator.instance.auth.signInWithEmail(email, pass);
    } catch (e) {
      if (ServiceLocator.instance.auth.currentUid == null) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doGoogle() async {
    _unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      await ServiceLocator.instance.auth.signInWithGoogle();
    } catch (e) {
      if (ServiceLocator.instance.auth.currentUid == null) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kb = MediaQuery.of(context).viewInsets.bottom; // altura do teclado

    return Scaffold(
      // mantemos o layout fixo; nós próprios gerimos o scroll/inset
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: _busy ? null : () {
              Navigator.of(context).pushNamed(SignUpScreen.route);
            },
            child: const Text('Ainda não tens conta?  Criar'),
          ),
        ],
      ),
      body: SafeArea(
        // remove insets automáticos para o Scaffold não “empurrar” nada
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
                    // Logo
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

                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(_error!, style: TextStyle(color: cs.error), textAlign: TextAlign.center),
                      ),

                    FilledButton(
                      onPressed: _busy ? null : _doSignIn,
                      child: _busy
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Entrar'),
                    ),
                    const SizedBox(height: 8),
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
