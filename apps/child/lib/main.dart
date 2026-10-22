import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/auth_screen.dart';
import 'screens/protection_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  await SupabaseConfig.init();
  await SupabaseService.instance.init();
  await LocalFamilyStore.instance.init();
  runApp(const ChildApp());
}

class ChildApp extends StatefulWidget {
  const ChildApp({super.key});

  @override
  State<ChildApp> createState() => _ChildAppState();
}

class _ChildAppState extends State<ChildApp> {
  ThemeMode _themeMode = ThemeMode.light;
  String _localeCode = 'en';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _themeMode = preferences.getBool('child_dark_mode') == true
          ? ThemeMode.dark
          : ThemeMode.light;
      _localeCode = preferences.getString('child_locale') == 'hi' ? 'hi' : 'en';
    });
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    unawaited(SharedPreferences.getInstance().then(
      (preferences) =>
          preferences.setBool('child_dark_mode', mode == ThemeMode.dark),
    ));
  }

  void _setLocaleCode(String code) {
    setState(() => _localeCode = code);
    unawaited(SharedPreferences.getInstance().then(
      (preferences) => preferences.setString('child_locale', code),
    ));
  }

  ThemeData _theme(Brightness brightness) =>
      AppPalette.theme(brightness: brightness);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Guard Child',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _themeMode,
      locale: Locale(_localeCode),
      supportedLocales: const [Locale('en'), Locale('hi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: _Root(
        localeCode: _localeCode,
        themeMode: _themeMode,
        onLocaleChanged: _setLocaleCode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root({
    required this.localeCode,
    required this.themeMode,
    required this.onLocaleChanged,
    required this.onThemeModeChanged,
  });

  final String localeCode;
  final ThemeMode themeMode;
  final ValueChanged<String> onLocaleChanged;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    return StreamBuilder<Profile?>(
      stream: auth.authStateChanges,
      builder: (context, snapshot) {
        final session = snapshot.data ?? auth.user;
        if (session == null || !session.isChild) {
          return const ChildAuthScreen();
        }
        return ProtectionScreen(
          localeCode: localeCode,
          themeMode: themeMode,
          onLocaleChanged: onLocaleChanged,
          onThemeModeChanged: onThemeModeChanged,
        );
      },
    );
  }
}
