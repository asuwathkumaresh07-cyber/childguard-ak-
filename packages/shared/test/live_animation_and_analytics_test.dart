import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AnimatedAlertTriangle renders and animates', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AnimatedAlertTriangle(size: 40),
        ),
      ),
    );

    expect(find.byType(AnimatedAlertTriangle), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('LiveAlertBanner renders with moving triangle and actions',
      (tester) async {
    var reviewed = false;
    var dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveAlertBanner(
            title: 'Critical Protection Alert',
            message: 'Child VPN was turned off unexpectedly',
            childName: 'Alex',
            onView: () => reviewed = true,
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );

    expect(find.text('Critical Protection Alert'), findsOneWidget);
    expect(find.text('Child VPN was turned off unexpectedly'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.byType(AnimatedAlertTriangle), findsOneWidget);

    await tester.tap(find.text('Review'));
    expect(reviewed, isTrue);

    await tester.tap(find.byIcon(Icons.close));
    expect(dismissed, isTrue);
  });

  testWidgets('GuardianCharacter renders in safe and alert moods',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GuardianCharacter(size: 80, mood: GuardianMood.safe),
        ),
      ),
    );

    expect(find.byType(GuardianCharacter), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('DualUsageChart renders daily bar and hourly points',
      (tester) async {
    final now = DateTime.now();
    final sampleLogs = [
      AppUsageLog(
        id: 'log-1',
        childId: 'child-1',
        familyId: 'family-1',
        packageName: 'com.example.youtube',
        appLabel: 'YouTube',
        startedAt: now.subtract(const Duration(hours: 2)),
        durationSeconds: 1800, // 30 min
      ),
      AppUsageLog(
        id: 'log-2',
        childId: 'child-1',
        familyId: 'family-1',
        packageName: 'com.example.chrome',
        appLabel: 'Chrome',
        startedAt: now.subtract(const Duration(days: 1, hours: 3)),
        durationSeconds: 3600, // 1 hr
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DualUsageChart(
              logs: sampleLogs,
              title: 'Test Analytics',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Test Analytics'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Hourly'), findsOneWidget);
    expect(find.text('Both Graphs'), findsNothing);

    // Switch to Daily Bar only
    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();
    expect(find.text('Daily Usage (Bar Graph)'), findsOneWidget);

    // Switch to Hourly Points only
    await tester.tap(find.text('Hourly'));
    await tester.pumpAndSettle();
    expect(find.text('Hourly Usage (Point Graph)'), findsOneWidget);
  });

  testWidgets('CategorizedLogsView switches between Live Log and Usage Log',
      (tester) async {
    final now = DateTime.now();
    final sampleApps = [
      AppUsageLog(
        id: 'app-1',
        childId: 'child-1',
        familyId: 'family-1',
        packageName: 'com.android.chrome',
        appLabel: 'Chrome',
        startedAt: now,
        durationSeconds: 1200,
      ),
    ];
    final sampleDomains = [
      DomainLog(
        id: 'domain-1',
        childId: 'child-1',
        familyId: 'family-1',
        domain: 'gamezone.com',
        action: 'blocked',
        occurredAt: now,
      ),
    ];
    final sampleTamper = [
      ChildTamperEvent(
        id: 'tamper-1',
        childId: 'child-1',
        familyId: 'family-1',
        eventType: 'vpn_disabled',
        occurredAt: now,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategorizedLogsView(
            appLogs: sampleApps,
            domainLogs: sampleDomains,
            tamperEvents: sampleTamper,
            childName: 'Alex',
          ),
        ),
      ),
    );

    // Initial state: Live Log category
    expect(find.text('Live Log'), findsOneWidget);
    expect(find.text('gamezone.com'), findsOneWidget);
    expect(find.text('VPN Protection Turned Off'), findsOneWidget);

    // Switch to Usage Log category
    await tester.tap(find.text('Usage Graph'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Hourly'), findsOneWidget);
    expect(find.text('Monthly'), findsNothing);

    // Switch to Hourly period
    await tester.tap(find.text('Hourly'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Hourly Usage (Point Graph)'), findsOneWidget);

    // Return to the daily graph without a duplicate usage list.
    await tester.tap(find.text('Daily'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Daily Usage (Bar Graph)'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('VPN status unknown'), findsOneWidget);
  });
}
