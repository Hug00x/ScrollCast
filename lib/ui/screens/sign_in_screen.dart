import 'package:flutter/material.dart';
import '../../main.dart';
import '../app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _unfocus() {
    final f = FocusScope.of(context);
    if (!f.hasPrimaryFocus && f.focusedChild != null) {
      f.unfocus();
    }
  }

  Future<List<String>> _safeFetchMethods(String email) async {
    // Protege contra emails vazios/mal formatados que às vezes causam estados esquisitos
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

      // dica de UX: se a conta é Google, avisa e não tenta password
      final methods = await _safeFetchMethods(email);
      if (methods.contains('google.com')) {
        setState(() => _error = 'Esta conta entra com Google. Usa "Continuar com Google".');
        return;
      }

      await ServiceLocator.instance.auth.signInWithEmail(email, pass);
    } catch (e) {
      // Só mostra erro se de facto não ficou autenticado
      if (ServiceLocator.instance.auth.currentUid == null) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
        setState(() => _error = 'Este email já está associado a uma conta Google. Usa "Continuar com Google".');
        return;
      }

      await ServiceLocator.instance.auth.signUpWithEmail(email, pass);

      // validação pós-criação (defensivo)
      if (ServiceLocator.instance.auth.currentUid == null) {
        throw Exception('Falha a criar conta (estado inválido).');
      }
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
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 24)
                      ],
                    ),
                    child: Image.asset(
                      'assets/scrollcast_with_name.png',
                      width: 200,
                      height: 200,
                    ),
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
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _busy ? null : _doSignIn(),
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  const SizedBox(height: 12),

                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(color: cs.error),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  FilledButton(
                    onPressed: _busy ? null : _doSignIn,
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Entrar'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _doSignUp,
                    child: const Text('Criar conta com email'),
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
    );
  }
}
