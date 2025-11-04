// ui/screens/sign_in_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
// The code below intentionally uses the BuildContext across an awaited
// dialog call when handling an account-exists-with-different-credential
// flow; we've guarded with `mounted` afterwards. Suppress the lint for
// the file to avoid spurious analyzer warnings here.
// ignore_for_file: use_build_context_synchronously

import '../../main.dart';
import '../auth_error_messages.dart';
import '../../services/auth_service.dart' show AccountExistsWithDifferentCredential;
import 'dart:async';
import 'home_shell.dart';

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
      _goHomeIfLogged(); // ⬅️ navega já
    } catch (e) {
      if (ServiceLocator.instance.auth.currentUid == null) {
        setState(() => _error = friendlyAuthMessage(e));
      } else {
        _goHomeIfLogged();
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
      _goHomeIfLogged(); // ⬅️ navega já
    } catch (e) {
      // Special-case the account-exists-with-different-credential flow so we
      // can offer to link the Google credential to an existing email/password
      // account.
      if (e is AccountExistsWithDifferentCredential) {
        final email = e.email;
        final pending = e.pendingCredential;
        // Ask the user for the password of the existing account so we can
        // sign them in and then link the Google credential.
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

  if (!mounted) return;

  if (pass != null && pass.isNotEmpty) {
          try {
            await ServiceLocator.instance.auth.signInWithEmail(email ?? '', pass);
            // Now link the pending Google credential
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              await user.linkWithCredential(pending);
            }
            _goHomeIfLogged();
            return;
          } catch (linkErr) {
            setState(() => _error = friendlyAuthMessage(linkErr));
            return;
          }
        }

        // user cancelled or didn't provide password
        setState(() => _error = 'Operação cancelada.');
        return;
      }

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
