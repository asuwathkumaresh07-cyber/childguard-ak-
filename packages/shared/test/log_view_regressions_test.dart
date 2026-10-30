import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

Widget frame(Widget body, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
        theme: AppPalette.theme(brightness: brightness),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                disableAnimations: true, textScaler: TextScaler.linear(1.5)),
            child: child!),
        home: Scaffold(body: body));

void main() {
  final log = AppUsageLog(
      id: 'app',
      childId: 'child',
      familyId: 'family',
      packageName: 'com.example.learning',
      appLabel:
          'A very long educational application name for reading and learning',
      startedAt: DateTime(2026, 9, 20),
      durationSeconds: 1800);
  for (final brightness in Brightness.values) {
    testWidgets(
        'Live Log and Usage Graph have readable selected text and icons in $brightness',
        (tester) async {
      await tester.pumpWidget(
          frame(CategorizedLogsView(appLogs: [log]), brightness: brightness));
      for (final tab in ['live', 'usage']) {
        final finder = find.byKey(ValueKey('log-category-$tab'));
        await tester.tap(finder);
        await tester.pumpAndSettle();
        final box = tester.widget<AnimatedContainer>(find.descendant(
            of: finder, matching: find.byType(AnimatedContainer)));
        final background = (box.decoration as BoxDecoration).color!;
        final text = tester.widget<Text>(
            find.descendant(of: finder, matching: find.byType(Text)));
        final a = background.computeLuminance();
        final b = text.style!.color!.computeLuminance();
        expect((math.max(a, b) + .05) / (math.min(a, b) + .05),
            greaterThanOrEqualTo(4.5));
        if (tab == 'usage') {
          final context = tester.element(find.descendant(
              of: finder, matching: find.byIcon(Icons.bar_chart_rounded)));
          expect(IconTheme.of(context).color, text.style!.color);
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'search stays visible after switching categories and quick app block works',
      (tester) async {
    var blocked = 0;
    await tester.pumpWidget(frame(CategorizedLogsView(
        appLogs: [log],
        onBlockApp: (package, label) {
          expect(package, log.packageName);
          blocked++;
        })));
    await tester.enterText(find.byType(TextField), 'reading');
    await tester.pump();
    await tester.tap(find.text('Usage Graph'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Live Log'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'reading');
    await tester.tap(find.byTooltip('Block app'));
    expect(blocked, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('live rows and empty state fit a narrow phone with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(frame(CategorizedLogsView(
        appLogs: [log],
        onBlockApp: (_, __) {},
        deviceStatus: ChildDeviceStatus(
            childId: 'child',
            familyId: 'family',
            vpnEnabled: false,
            usageAccessEnabled: true,
            accessibilityEnabled: false,
            lastSeenAt: DateTime(2026, 9, 20)))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField), 'no matching event');
    await tester.pumpAndSettle();
    expect(find.text('No events match your filter'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
