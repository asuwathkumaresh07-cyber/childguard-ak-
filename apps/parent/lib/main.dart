import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared/shared.dart';

import 'services/parent_push_service.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.white,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  await SupabaseConfig.init();
  await SupabaseService.instance.init();
  await LocalFamilyStore.instance.init();
  await ParentPushService.initialize();
  runApp(const ParentApp());
}

class ParentApp extends StatelessWidget {
  const ParentApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Family Guard Parent',
        debugShowCheckedModeBanner: false,
        theme: AppPalette.theme(),
        themeMode: ThemeMode.light,
        home: const _Root(),
      );
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
