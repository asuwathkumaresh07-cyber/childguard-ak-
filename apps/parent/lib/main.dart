import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import 'services/parent_push_service.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.init();
  await SupabaseService.instance.init();
  await LocalFamilyStore.instance.init();
  await ParentPushService.initialize();
  runApp(const ParentApp());
}

class ParentApp extends StatelessWidget {
  const ParentApp({super.key});

  @override
  Widget build(BuildContext context) {
    const neonRed = Color(0xFFFF1744);
    const cyberBlue = Color(0xFF0066FF);

    final scheme = ColorScheme.fromSeed(
      seedColor: neonRed,
      brightness: Brightness.light,
    ).copyWith(
      primary: neonRed, // Red dominant!
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFFFE8EC),
      onPrimaryContainer: const Color(0xFFC00028),
      secondary: cyberBlue, // Blue accent!
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFE8F1FF),
      onSecondaryContainer: const Color(0xFF0044B3),
      tertiary: const Color(0xFFFF5277),
      surface: Colors.white,
      onSurface: const Color(0xFF0F172A),
    );
    return MaterialApp(
      title: 'Family Guard Parent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white.withValues(alpha: .92),
          foregroundColor: const Color(0xFF0F172A),
          elevation: 0,
          centerTitle: false,
          titleTextStyle: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white.withValues(alpha: .92),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(
              color: neonRed.withValues(alpha: .22),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: .94),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: neonRed.withValues(alpha: .25),
            ),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide(color: neonRed, width: 1.8),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: neonRed,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        tabBarTheme: TabBarThemeData(
          indicatorColor: neonRed,
          labelColor: neonRed,
          unselectedLabelColor: const Color(0xFF64748B),
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    return StreamBuilder<Profile?>(
      stream: auth.authStateChanges,
      builder: (context, snapshot) {
        final session = snapshot.data ?? auth.user;
        if (session == null || !session.isParent) {
          return const AuthScreen();
        }
        return const HomeScreen();
      },
    );
  }
}
