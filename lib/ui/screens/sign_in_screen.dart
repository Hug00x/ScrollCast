import 'package:flutter/material.dart';
import '../../main.dart';
import '../app_theme.dart';

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
  String? _error;

  Future<void> _doSignIn() async {
    setState(() { _busy = true; _error = null; });
    try {
      await ServiceLocator.instance.auth.signInWithEmail(_email.text.trim(), _pass.text.trim());
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doSignUp() async {
    setState(() { _busy = true; _error = null; });
    try {
      await ServiceLocator.instance.auth.signUpWithEmail(_email.text.trim(), _pass.text.trim());
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doGoogle() async {
    setState(() { _busy = true; _error = null; });
    try {
      await ServiceLocator.instance.auth.signInWithGoogle();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
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
                

                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Text(_error!, style: TextStyle(color: cs.error)),

                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _doSignIn,
                    child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Entrar'),
                  ),
                  TextButton(onPressed: _busy ? null : _doSignUp, child: const Text('Criar conta com email')),
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
    );
  }
}
