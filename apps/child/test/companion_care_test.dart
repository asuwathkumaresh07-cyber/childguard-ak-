import 'dart:io';
import 'dart:ui' as ui;
import 'package:child/widgets/companion_care.dart';
import 'package:child/widgets/companion_care_state.dart';
import 'package:child/widgets/companion_pet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget frame(Widget child) => MaterialApp(
    theme: Platform.environment['SAVE_PET_PREVIEW'] == '1'
        ? AppPalette.theme().copyWith(
            textTheme:
                AppPalette.theme().textTheme.apply(fontFamily: 'CarePreview'))
        : AppPalette.theme(),
    builder: (context, page) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: page!),
    home: child);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
      'water reminder logs a break and the buddy offers a useful care panel',
      (tester) async {
    var now = DateTime(2026, 10, 23, 10);
    final state = CompanionCareState(now)
      ..waterSeconds = 1800
      ..eyesEnabled = false
      ..checkInEnabled = false;
    SharedPreferences.setMockInitialValues(
        {'child_companion_care_test': state.encode()});
    await tester.pumpWidget(frame(CompanionCare(
        childId: 'test',
        vpnEnabled: true,
        permissionsReady: true,
        pendingTasks: 2,
        now: () => now,
        onTasks: () {},
        onProtection: () {},
        child: const Scaffold(body: Text('Home')))));
    await tester.pumpAndSettle();
    now = now.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Time for a little water break?'), findsNWidgets(2));
    await tester.tap(find.text('I had some water'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(
        CompanionCareState.decode(
                prefs.getString('child_companion_care_test'), now)
            .waterBreaks,
        1);
    await tester.tap(find.bySemanticsLabel(RegExp('.*Drag to move.*')));
    await tester.pumpAndSettle();
    expect(find.text('Protection is on'), findsOneWidget);
    expect(find.text('2 tasks waiting'), findsOneWidget);
    expect(find.textContaining('1 water break'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('background time does not count toward hydration prompts',
      (tester) async {
    var now = DateTime(2026, 10, 23, 10);
    final state = CompanionCareState(now)
      ..waterSeconds = 1700
      ..eyesEnabled = false
      ..checkInEnabled = false;
    SharedPreferences.setMockInitialValues(
        {'child_companion_care_test': state.encode()});
    await tester.pumpWidget(frame(CompanionCare(
        childId: 'test',
        vpnEnabled: true,
        permissionsReady: true,
        now: () => now,
        onTasks: () {},
        onProtection: () {},
        child: const Scaffold())));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(hours: 2));
    await tester.pump(const Duration(hours: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('I had some water'), findsNothing);
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(find.text('I had some water'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('cancelled check-in is snoozed and is not treated as shared',
      (tester) async {
    var now = DateTime(2026, 10, 23, 10);
    final state = CompanionCareState(now)
      ..checkInSeconds = CompanionCareState.checkInInterval.inSeconds
      ..waterEnabled = false
      ..eyesEnabled = false;
    SharedPreferences.setMockInitialValues(
        {'child_companion_care_test': state.encode()});
    var asked = 0;
    await tester.pumpWidget(frame(CompanionCare(
        childId: 'test',
        vpnEnabled: true,
        permissionsReady: true,
        now: () => now,
        onTasks: () {},
        onProtection: () {},
        onCheckIn: () async {
          asked++;
          return false;
        },
        child: const Scaffold())));
    await tester.pumpAndSettle();
    now = now.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    await tester.tap(find.text('Check in'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final saved = CompanionCareState.decode(
        prefs.getString('child_companion_care_test'), now);
    expect(asked, 1);
    expect(saved.checkInSeconds, greaterThanOrEqualTo(1800));
    expect(saved.snoozed[CareReminder.checkIn],
        now.add(const Duration(minutes: 5)));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('eye rest completes after twenty seconds and fits a small screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(frame(const Scaffold(body: EyeRestDialog())));
    expect(find.text('Done'), findsNothing);
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('Nice little break!'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'care dashboard fits a narrow phone and renders the happy sourced pet',
      (tester) async {
    tester.view.physicalSize = const Size(360, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (Platform.environment['SAVE_PET_PREVIEW'] == '1') {
      await tester.runAsync(() async {
        final file = File('C:/Windows/Fonts/segoeui.ttf');
        if (await file.exists()) {
          final loader = FontLoader('CarePreview')
            ..addFont(file
                .readAsBytes()
                .then((bytes) => ByteData.view(bytes.buffer)));
          await loader.load();
        }
      });
    }
    await tester.pumpWidget(frame(RepaintBoundary(
        key: const ValueKey('care-preview'),
        child: CompanionCare(
            childId: 'test',
            vpnEnabled: true,
            permissionsReady: true,
            pendingTasks: 1,
            onTasks: () {},
            onProtection: () {},
            onCheckIn: () async => false,
            child: const Scaffold(
                body: Center(child: Text('Your daily buddy')))))));
    await tester.runAsync(() => precacheImage(
        AssetImage(CompanionPet.corgi.assetPath),
        tester.element(find.byType(CompanionCare))));
    await tester.pumpAndSettle();
    if (Platform.environment['SAVE_PET_PREVIEW'] == '1') {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('care-preview')));
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 2);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        await File('../../artifacts/happy-buddy-preview.png')
            .writeAsBytes(data!.buffer.asUint8List());
        img.dispose();
      });
    }
    await tester.tap(find.bySemanticsLabel(RegExp('.*Drag to move.*')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Eye-rest reminders'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('a recently shared check-in postpones the next mood prompt',
      (tester) async {
    var now = DateTime(2026, 10, 23, 10);
    final state = CompanionCareState(now)
      ..checkInSeconds = CompanionCareState.checkInInterval.inSeconds
      ..waterEnabled = false
      ..eyesEnabled = false;
    SharedPreferences.setMockInitialValues(
        {'child_companion_care_test': state.encode()});
    var asked = 0;
    await tester.pumpWidget(frame(CompanionCare(
        childId: 'test',
        vpnEnabled: true,
        permissionsReady: true,
        latestCheckInAt: now,
        now: () => now,
        onTasks: () {},
        onProtection: () {},
        onCheckIn: () async {
          asked++;
          return true;
        },
        child: const Scaffold())));
    await tester.pumpAndSettle();
    now = now.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Check in'), findsNothing);
    expect(asked, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(
        CompanionCareState.decode(
                prefs.getString('child_companion_care_test'), now)
            .checkInSeconds,
        30);
    await tester.pumpWidget(const SizedBox());
  });
}
