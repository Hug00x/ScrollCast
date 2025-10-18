// ui/screens/onboarding_start_screen.dart
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';

import '../../main.dart';
import 'home_shell.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';

class OnboardingStartScreen extends StatefulWidget {
  static const route = '/onboarding';
  const OnboardingStartScreen({super.key});

  @override
  State<OnboardingStartScreen> createState() => _OnboardingStartScreenState();
}

class _OnboardingStartScreenState extends State<OnboardingStartScreen>
    with WidgetsBindingObserver {
  bool _checkingNet = true;
  bool _online = true;
  bool _navigated = false;

  StreamSubscription<String?>? _authSub;

  // >>> NOVO: “watcher” de conectividade por ping periódico
  Timer? _netTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Se já está autenticado, segue para a Home.
    final uid = ServiceLocator.instance.auth.currentUid;
    if (uid != null) {
      _goHome();
    }

    // Escuta auth: se fizer login via SignIn/Google, navega logo.
    _authSub = ServiceLocator.instance.auth
        .authStateChanges()
        .listen((uid) {
      if (uid != null) _goHome();
    });

    _checkConnectivity();   // 1ª verificação
    _startLiveNetWatch();   // monitorização contínua
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _netTimer?.cancel();
    super.dispose();
  }

  // Pausa/retoma o watcher conforme o estado da app
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startLiveNetWatch();
      _probeNet(); // força atualização imediata ao voltar
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _netTimer?.cancel();
      _netTimer = null;
    }
  }

  // Verificação “manual” com spinner (mantida)
  Future<void> _checkConnectivity() async {
    setState(() => _checkingNet = true);
    try {
      final res = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 3));
      _online = res.isNotEmpty && res.first.rawAddress.isNotEmpty;
    } catch (_) {
      _online = false;
    } finally {
      if (mounted) setState(() => _checkingNet = false);
    }
  }

  // >>> NOVO: ping leve, sem spinner; só faz setState quando muda
  Future<void> _probeNet() async {
    bool newOnline = _online;
    try {
      final res = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 2));
      newOnline = res.isNotEmpty && res.first.rawAddress.isNotEmpty;
    } catch (_) {
      newOnline = false;
    }
    if (!mounted) return;
    if (newOnline != _online) {
      setState(() => _online = newOnline);
    }
  }

  // >>> NOVO: inicia/renova o timer periódico
  void _startLiveNetWatch() {
    _netTimer?.cancel();
    _netTimer = Timer.periodic(const Duration(seconds: 3), (_) => _probeNet());
  }

  void _goHome() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell(initialIndex: 1)),
      (_) => false,
    );
  }

  Future<void> _enterGuest() async {
    // Convidado: dados locais (DatabaseServiceImpl usa _anon quando não há UID).
    _goHome();
  }

  void _goToSignIn() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignInScreen()));
  }

  void _goToSignUp() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignUpScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pad = MediaQuery.of(context).padding;
    final disabled = !_online || _checkingNet;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + pad.bottom),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo (a tua imagem já tem título – não duplicamos)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F2230),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24)],
                    ),
                    child: Image.asset('assets/scrollcast_with_name.png', width: 220, height: 220),
                  ),
                  const SizedBox(height: 32),

                  // Criar conta
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: disabled ? null : _goToSignUp,
                      child: _checkingNet
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Criar conta'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Entrar
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: disabled ? null : _goToSignIn,
                      child: const Text('Entrar'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Convidado (texto sem borda)
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _enterGuest,
                      child: const Text('Entrar como Convidado'),
                    ),
                  ),

                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _checkConnectivity,
                    icon: Icon(_online ? Icons.wifi : Icons.wifi_off, color: cs.primary),
                    label: Text(_online ? 'Ligado' : 'Sem internet'),
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
