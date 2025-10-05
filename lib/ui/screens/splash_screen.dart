import 'dart:async';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import 'library_screen.dart';

class SplashScreen extends StatefulWidget {
  static const route = '/splash';
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _scale = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));

    _ctrl.forward();
    Timer(const Duration(milliseconds: 1600), () {
      if (mounted) Navigator.pushReplacementNamed(context, LibraryScreen.route);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
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
                  child: Image.asset(
                    'assets/scrollcast_logo.png',
                    width: 160,
                    height: 160,
                  ),
                ),
                const SizedBox(height: 20),
                // Texto com gradiente nas cores do logo
                ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    colors: [AppColors.accent, AppColors.primary, AppColors.secondary],
                  ).createShader(rect),
                  child: const Text(
                    'ScrollCast',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: Colors.white, // será mascarado
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
