import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF0B1A24);
  static const primary    = Color(0xFF00C27A);
  static const secondary  = Color(0xFF00B8D9);
  static const accent     = Color(0xFFFFD64D);
}

ThemeData buildAppTheme() {
  final base = ThemeData.dark();
  final scheme = ColorScheme.fromSeed(
  seedColor: AppColors.primary,
  brightness: Brightness.dark,
  primary: AppColors.primary,
  secondary: AppColors.secondary,
  surface: const Color(0xFF0F2230),
    onPrimary: Colors.black,
    onSecondary: Colors.black,
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
      iconTheme: IconThemeData(color: Colors.white),
      centerTitle: false,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.black,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: AppColors.primary,
      thumbColor: AppColors.accent,
  overlayColor: AppColors.primary.withAlpha((.2 * 255).round()),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF132B3A),
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}

// <-- NOVO: versão clara
ThemeData buildLightAppTheme() {
  final base = ThemeData.light();
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
    primary: AppColors.primary,
    secondary: AppColors.secondary,
  );
  return base.copyWith(
    colorScheme: scheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      elevation: 0,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black),
      iconTheme: IconThemeData(color: Colors.black),
      centerTitle: false,
    ),
  );
}
