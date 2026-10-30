import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent/screens/home_screen.dart';
import 'package:parent/screens/child_detail_screen.dart';
import 'package:parent/screens/blocked_apps_screen.dart';
import 'package:parent/screens/auth_screen.dart';
import 'package:shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

const parentProfile = Profile(
    id: 'parent',
    role: 'parent',
    displayName: 'A parent with a very long display name');

class TestFamily extends FamilyService {
  @override
  Future<List<DomainLog>> fetchDomainLogs(
          {required String familyId,
          String? childId,
          int? limit = 100}) async =>
      [];
  @override
  Future<List<AppUsageLog>> fetchAppUsageLogs(
          {required String familyId,
          String? childId,
          int? limit = 100}) async =>
      [];
  @override
  Future<List<String>> fetchChildBlockDomains(
          {required String familyId, required String childId}) async =>
      [];
  @override
  Future<List<String>> fetchChildBlockedAppPackages(
          {required String familyId, required String childId}) async =>
      [];
  @override
  Future<List<String>> fetchBlockedCategories([String? familyId]) async => [];
  @override
  Future<List<String>> fetchBlockedAppPackages(String familyId) async => [];
  @override
  Future<List<String>> fetchChildBlockedCategories(
          {required String familyId, required String childId}) async =>
      [];
  @override
  bool get isUsingSupabase => false;
  @override
  Future<void> reload() async {}
  @override
  Future<Profile?> fetchMyProfile() async => parentProfile;
  @override
  Future<Family?> fetchMyFamily() async => const Family(
      id: 'family', ownerId: 'parent', name: 'Family with a longer name');
  @override
  Future<List<FamilyMember>> fetchChildren(String familyId) async => const [
        FamilyMember(
            id: 'member',
            familyId: 'family',
            profileId: 'child',
            profile: Profile(
                id: 'child',
                role: 'child',
                displayName: 'Alexandra with a very long name')),
      ];
}

class TestAuth extends AuthService {
  @override
  Future<Profile?> ensureProfile() async => parentProfile;
}

class DelayedAppsFamily extends TestFamily {
  final result = Completer<List<BlockedAppEntry>>();
  @override
  Future<List<BlockedAppEntry>> fetchBlockedApps(String familyId) =>
      result.future;
}

Widget frame(Widget child) {
  var theme = AppPalette.theme();
  if (Platform.environment['SAVE_PARENT_PREVIEW'] == '1') {
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'ParentPreview'),
      appBarTheme: theme.appBarTheme.copyWith(
          titleTextStyle: theme.appBarTheme.titleTextStyle
              ?.copyWith(fontFamily: 'ParentPreview')),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              textStyle: const TextStyle(
                  fontFamily: 'ParentPreview', fontWeight: FontWeight.w700))),
      floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
          extendedTextStyle: const TextStyle(
              fontFamily: 'ParentPreview', fontWeight: FontWeight.w700)),
    );
  }
  return MaterialApp(
      theme: theme,
      builder: (context, page) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              disableAnimations: true, textScaler: TextScaler.linear(1.5)),
          child: page!),
      home:
          RepaintBoundary(key: const ValueKey('parent-preview'), child: child));
}

Future<void> preview(WidgetTester tester, String name) async {
  if (Platform.environment['SAVE_PARENT_PREVIEW'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('parent-preview')));
  await tester.runAsync(() async {
    final picture = await boundary.toImage(pixelRatio: 2);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    await File('../../artifacts/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> prepare(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (Platform.environment['SAVE_PARENT_PREVIEW'] == '1') {
      await tester.runAsync(() async {
        for (final entry in {
          'ParentPreview': 'C:/Windows/Fonts/segoeui.ttf',
          'MaterialIcons':
              'C:/Users/Acer/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
        }.entries) {
          final loader = FontLoader(entry.key)
            ..addFont(File(entry.value)
                .readAsBytes()
                .then((bytes) => ByteData.sublistView(bytes)));
          await loader.load();
        }
      });
    }
  }

  testWidgets(
      'dashboard scrolls without overflow and its navigation drawer opens',
      (tester) async {
    await prepare(tester);
    await tester.pumpWidget(frame(
        HomeScreen(familyService: TestFamily(), authService: TestAuth())));
    await tester.pumpAndSettle();
    await tester.runAsync(() => precacheImage(
        const AssetImage('assets/branding/parent-logo.png'),
        tester.element(find.byType(HomeScreen))));
    await tester.pump();
    await preview(tester, 'parent-dashboard-fixed');
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 10; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -350));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('Dashboard'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('activity tabs and unknown VPN status fit a narrow screen',
      (tester) async {
    await prepare(tester);
    await tester.pumpWidget(frame(ChildDetailScreen(
        familyId: 'family',
        childId: 'child',
        childName: 'Alexandra with a very long name',
        familyService: TestFamily())));
    await tester.pumpAndSettle();
    await preview(tester, 'parent-live-log-fixed');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Usage Graph'));
    await tester.pumpAndSettle();
    await preview(tester, 'parent-usage-graph-fixed');
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Hourly'));
    await tester.tap(find.text('Hourly'));
    await tester.pumpAndSettle();
    expect(find.text('Hourly Usage (Point Graph)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'closing blocked apps during a pending load does not set state after dispose',
      (tester) async {
    final family = DelayedAppsFamily();
    await tester.pumpWidget(
        frame(BlockedAppsScreen(familyId: 'family', familyService: family)));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    family.result.complete([]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('parent login form fits large text on a narrow phone',
      (tester) async {
    await prepare(tester);
    await tester.pumpWidget(frame(const AuthScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Create Parent Account'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
