import 'package:flutter/material.dart';

/// White surfaces, blue controls, and a small red accent for warnings.
abstract final class AppPalette {
  static const blue = Color(0xFF2563EB);
  static const navy = Color(0xFF172B4D);
  static const background = Color(0xFFF5F8FF);
  static const paleBlue = Color(0xFFEAF1FF);
  static const border = Color(0xFFDCE6F7);
  static const red = Color(0xFFDC3545);
  static const paleRed = Color(0xFFFFF0F2);

  static ThemeData theme({Brightness brightness = Brightness.light}) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(seedColor: blue, brightness: brightness).copyWith(
      primary: dark ? const Color(0xFF8AB4FF) : blue,
      onPrimary: dark ? navy : Colors.white,
      primaryContainer: dark ? const Color(0xFF20385F) : paleBlue,
      onPrimaryContainer: dark ? Colors.white : navy,
      secondary: dark ? const Color(0xFF8AB4FF) : blue,
      secondaryContainer: dark ? const Color(0xFF20385F) : paleBlue,
      tertiary: red,
      error: red,
      errorContainer: dark ? const Color(0xFF491C27) : paleRed,
      surface: dark ? const Color(0xFF142238) : Colors.white,
      onSurface: dark ? Colors.white : navy,
      outlineVariant: dark ? const Color(0xFF30425D) : border,
    );
    final rounded =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF0D1829) : background,
      iconTheme: IconThemeData(color: scheme.primary, size: 22),
      appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
              color: scheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w700)),
      cardTheme: CardThemeData(
          color: scheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape:
              rounded.copyWith(side: BorderSide(color: scheme.outlineVariant))),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: scheme.outlineVariant)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: scheme.primary, width: 1.5))),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              shape: rounded,
              textStyle: const TextStyle(fontWeight: FontWeight.w700))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48), shape: rounded)),
      tabBarTheme: TabBarThemeData(
          indicatorColor: scheme.primary,
          labelColor: scheme.primary,
          unselectedLabelColor: scheme.onSurfaceVariant,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      navigationBarTheme: NavigationBarThemeData(
          backgroundColor: scheme.surface,
          indicatorColor: scheme.primaryContainer),
      dividerTheme:
          DividerThemeData(color: scheme.outlineVariant, thickness: 1),
    );
  }
}
