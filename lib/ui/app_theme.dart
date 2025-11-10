import 'package:flutter/material.dart';

/*
  app_theme.dart

  Propósito geral:
  - Centraliza as cores e a construção dos temas (claro e escuro) da app.
  - Torna fácil ajustar tokens de cor (AppColors) e a aparência global
    (AppBar, FAB, Slider, SnackBar) num único local.

  Notas de design:
  - Usamos `ColorScheme.fromSeed` para criar esquemas coerentes a partir de
    de uma cor base (`AppColors.primary`). Isso ajuda a manter harmonia entre
    cores primárias, secundárias e superfícies.
  - `buildAppTheme()` cria o tema escuro padrão da aplicação e aplica
    sobrecargas específicas (appBarTheme, sliderTheme, snackBarTheme, etc.).
  - `buildLightAppTheme()` fornece a versão clara com ajustes de AppBar
    apropriados para leitura em fundo claro.
*/

class AppColors {
  // Paleta centralizada
  static const background = Color(0xFF0B1A24);
  static const primary    = Color(0xFF00C27A);
  static const secondary  = Color(0xFF00B8D9);
  static const accent     = Color(0xFFFFD64D);
}

// Constrói o tema escuro da aplicação.
ThemeData buildAppTheme() {
  // Base: partimos do ThemeData.dark() e então sobrepomos partes específicas.
  final base = ThemeData.dark();

  // Gerar um ColorScheme a partir de uma 'seed' (primary). Definimos
  // explicitamente 'surface' para controlar a cor dos painéis.
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
    // Aplicar o esquema de cores gerado
    colorScheme: scheme,

    // Cor de fundo do scaffold (área principal da app)
    scaffoldBackgroundColor: AppColors.background,

    // AppBar: transparente para um efeito suave. Título e ícones brancos no tema escuro para contraste.
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
      iconTheme: IconThemeData(color: Colors.white),
      centerTitle: false,
    ),

    // FAB: usamos a cor primária com foreground escuro (ícones pretos)
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.black,
    ),

    // Slider: ajustamos track/thumbnail/overlay para combinar com o tema e melhorar visibilidade.
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: AppColors.primary,
      thumbColor: AppColors.accent,
      // Overlay color representa a cor ao interagir com o thumb.
      overlayColor: AppColors.primary.withAlpha((.2 * 255).round()),
    ),

    // SnackBar: fundo escuro para encaixar visualmente com o esquema.
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF132B3A),
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}

// Versão clara do tema
ThemeData buildLightAppTheme() {
  final base = ThemeData.light();

  // ColorScheme para o tema claro, usando a mesma 'seed' para coerência.
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
    primary: AppColors.primary,
    secondary: AppColors.secondary,
  );

  return base.copyWith(
    colorScheme: scheme,
    // AppBar claro: fundo branco e texto preto
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      elevation: 0,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black),
      iconTheme: IconThemeData(color: Colors.black),
      centerTitle: false,
    ),
  );
}
