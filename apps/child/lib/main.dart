import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/auth_screen.dart';
import 'widgets/animated_companion_pet.dart';
import 'screens/protection_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerCompanionPetLicense();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.white,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
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
      _localeCode = preferences.getString('child_locale') == 'hi' ? 'hi' : 'en';
    });
  }

  void _setLocaleCode(String code) {
    setState(() => _localeCode = code);
    unawaited(SharedPreferences.getInstance().then(
      (preferences) => preferences.setString('child_locale', code),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Guard Child',
      debugShowCheckedModeBanner: false,
      theme: AppPalette.theme(),
      themeMode: ThemeMode.light,
      locale: Locale(_localeCode),
      supportedLocales: const [Locale('en'), Locale('hi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: _Root(
        localeCode: _localeCode,
        onLocaleChanged: _setLocaleCode,
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root({
    required this.localeCode,
    required this.onLocaleChanged,
  });

  final String localeCode;
  final ValueChanged<String> onLocaleChanged;

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
          onLocaleChanged: onLocaleChanged,
        );
      },
    );
  }
}
