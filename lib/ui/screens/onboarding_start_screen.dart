// ui/screens/onboarding_start_screen.dart
/*
  OnboardingStartScreen

  Propósito geral:
  - Apresenta o ecrã inicial da aplicação para novos utilizadores.
  - Verifica conectividade de rede, permite criar conta, entrar, ou
    continuar como convidado.
  - Observa o estado de autenticação para navegar automaticamente
    para a Home se o utilizador já estiver autenticado.

  Organização do ficheiro:
  - `OnboardingStartScreen`: widget de estado que orquestra verificações
    de conectividade, observação do auth, e navegação para os ecrãs
    de autenticação / home.
  - Implementa um "watcher" leve de conectividade (ping periódico)
    para atualizar o UI sem bloquear o início.
*/
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
  // ===== Estado básico =====
  // `_checkingNet`: quando true mostramos um spinner na verificação manual inicial.
  // `_online`: estado atual de conectividade (ping bem-sucedido).
  // `_navigated`: evita múltiplas navegações concorrentes.
  bool _checkingNet = true;
  bool _online = true;
  bool _navigated = false;

  // Subscrição do estado de autenticação: usada para reagir a logins que ocorram enquanto o ecrã está visível.
  StreamSubscription<String?>? _authSub;

  //"watcher" de conectividade — timer periódico que faz pings leves para atualizar `_online` sem bloquear a UI.
  Timer? _netTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // ===== Inicialização =====
    // 1) Observador de ciclo de vida para pausar/retomar o watcher de rede.
    // 2) Se já existir um UID válido, navegamos imediatamente para a Home.
    // 3) Inscrevemo-nos nas mudanças de autenticação para reagir a logins
    //    que ocorram a partir de outros ecrãs.
    final uid = ServiceLocator.instance.auth.currentUid;
    if (uid != null) {
      // Se já está autenticado, entra imediatamente.
      _goHome();
    }

    // Escuta mudanças de autenticação e navega automaticamente quando um UID válido é emitido.
    _authSub = ServiceLocator.instance.auth
        .authStateChanges()
        .listen((uid) {
      if (uid != null) _goHome();
    });

    // Inicia verificação de conectividade seguida de um watcher periódico que atualiza o estado silenciosamente.
    _checkConnectivity();
    _startLiveNetWatch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _netTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Quando a app volta do background, renovamos o watcher e forçamos uma verificação imediata.
    // Quando a app fica em pausa/inativa, paramos o timer para poupar recursos.
    if (state == AppLifecycleState.resumed) {
      _startLiveNetWatch();
      _probeNet(); // força atualização imediata ao voltar
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _netTimer?.cancel();
      _netTimer = null;
    }
  }

  Future<void> _checkConnectivity() async {
    // Verificação manual com spinner: usada por botões e na inicialização.
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
  Future<void> _probeNet() async {
    // Ping leve sem spinner. Só atualiza o estado se houver mudança para
    // evitar re-renderizações desnecessárias quando a conectividade é estável.
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

  void _startLiveNetWatch() {
    // Reinicia o timer periódico (3s) que chama `_probeNet`.
    _netTimer?.cancel();
    _netTimer = Timer.periodic(const Duration(seconds: 3), (_) => _probeNet());
  }

  void _goHome() {
    // Navega para o HomeShell e remove toda a stack de navegação anterior.
    // `_navigated` evita que a navegação seja disparada múltiplas vezes.
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell(initialIndex: 1)),
      (_) => false,
    );
  }

  Future<void> _enterGuest() async {
    // Entrar como convidado: a implementação do DatabaseService trata dados
    // locais para utilizadores anónimos. Aqui simplesmente navegamos para a Home.
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
    // ===== Build: árvore da UI =====
    // O ecrã centra um cartão com o logo e três ações principais: criar
    // conta, entrar e entrar como convidado. Há também um botão de estado
    // de conectividade que permite re-disparar a verificação manual.
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
                  // ----- Logo -----
                  // Container com decoração e a imagem e nome do logo.
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

                  // ----- Criar conta -----
                  // Botão principal para registar uma nova conta. Se uma verificação inicial
                  // de rede estiver em curso mostra um spinner em vez do texto.
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

                  // ----- Entrar -----
                  // Botão secundário para abrir o ecrã de login.
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: disabled ? null : _goToSignIn,
                      child: const Text('Entrar'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ----- Entrar como Convidado -----
                  // Permite usar a app sem autenticação; dados são mantidos
                  // localmente pelo serviço de base de dados.
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _enterGuest,
                      child: const Text('Entrar como Convidado'),
                    ),
                  ),

                  const SizedBox(height: 12),
                  // ----- Estado de conectividade -----
                  // Botão que mostra o estado atual e permite forçar
                  // uma verificação manual ao ser tocado.
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
