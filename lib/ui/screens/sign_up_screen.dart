// ui/screens/sign_up_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../main.dart';
import '../auth_error_messages.dart';
import 'home_shell.dart';

class SignUpScreen extends StatefulWidget {
  static const route = '/signup';
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
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

  void _goHomeIfLogged() {
    final uid = ServiceLocator.instance.auth.currentUid;
    if (uid != null && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell(initialIndex: 1)),
        (_) => false,
      );
    }
  }

  Future<List<String>> _safeFetchMethods(String email) async {
    if (email.isEmpty || !email.contains('@')) return const <String>[];
    try {
      return await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _doSignUp() async {
    _unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      final email = _email.text.trim();
      final pass = _pass.text.trim();

      final methods = await _safeFetchMethods(email);
      if (methods.contains('google.com')) {
        setState(() => _error = 'Este email já está associado a uma conta Google. Usa "Continuar com Google" no ecrã de entrada.');
        return;
      }

      await ServiceLocator.instance.auth.signUpWithEmail(email, pass);
      _goHomeIfLogged(); // ⬅️ navega logo
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

                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(_error!, style: TextStyle(color: cs.error), textAlign: TextAlign.center),
                      ),

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
