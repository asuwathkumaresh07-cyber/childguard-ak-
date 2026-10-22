import 'package:child/widgets/child_activity_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared/shared.dart';

void main() {
  testWidgets('switches graph mode and shows per-app sessions', (tester) async {
    await initializeDateFormatting();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 9);
    final log = AppUsageLog(
      id: 'usage-1',
      childId: 'child-1',
      familyId: 'family-1',
      packageName: 'com.example.video',
      appLabel: 'Video app',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 45)),
      durationSeconds: 2700,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChildActivityChart(logs: [log]),
          ),
        ),
      ),
    );

    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Hourly'), findsOneWidget);
    expect(find.text('Activity by app'), findsOneWidget);
    expect(find.text('Video app'), findsOneWidget);
    await tester.tap(find.text('Hourly').first);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Hourly Usage (Point Graph)'), findsOneWidget);
    await tester.tap(find.text('Video app'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.textContaining('Session · 45m'), findsOneWidget);
  });
}
