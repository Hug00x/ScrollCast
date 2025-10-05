import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF0B1A24); // navy escuro
  static const primary    = Color(0xFF00C27A); // verde
  static const secondary  = Color(0xFF00B8D9); // teal
  static const accent     = Color(0xFFFFD64D); // amarelo
}

ThemeData buildAppTheme() {
  final base = ThemeData.dark();

  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.dark,
    primary: AppColors.primary,
    secondary: AppColors.secondary,
    background: AppColors.background,
    surface: const Color(0xFF0F2230),
    onPrimary: Colors.black,
    onSecondary: Colors.black,
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.black,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: AppColors.primary,
      thumbColor: AppColors.accent,
      overlayColor: AppColors.primary.withOpacity(.2),
    ),
    toggleButtonsTheme: base.toggleButtonsTheme.copyWith(
      selectedColor: Colors.black,
      fillColor: AppColors.accent,
      color: Colors.white,
      borderColor: Colors.white24,
      selectedBorderColor: Colors.white54,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF132B3A),
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}
